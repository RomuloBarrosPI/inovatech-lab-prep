#!/usr/bin/env bash
# =============================================================================
# INOVATECH – Testa todas as combinações backend × frontend (laboratório)
#
# Para cada combinação (3 backends × 2 frontends = 6):
#   • inovatech-preparar-entrega (código PP distinto)
#   • Sobe o backend (porta dedicada, só 127.0.0.1) e confere HTTP local
#   • Sobe o frontend Vite (porta dedicada) e confere HTTP local
#   • inovatech-submit --dir (comprovante; sem depender de internet)
#
# Antes do laço: inovatech-verify e inovatech-versions (uma vez).
#
# Tráfego de rede: apenas HTTP para 127.0.0.1 (adequado ao dia da prova sem
# internet). npm/pip já devem estar satisfeitos pelo preparar-entrega.
#
# Variáveis opcionais:
#   INOVATECH_CODIGO_INICIAL   primeiro código PP usado (default: 31 → …36)
#   INOVATECH_NOME_COMPLETO    nome no comprovante (default abaixo)
#   INOVATECH_SKIP_SUBMIT      1=pula inovatech-submit (default: 0)
#   INOVATECH_SKIP_VERIFY      1=pula verify + versions no início (default: 0)
#
# Pré-requisitos: ~/inovatech completo; comandos inovatech-* no PATH; curl.
# =============================================================================

set -euo pipefail

INV_ROOT="${HOME}/inovatech"
NOME="${INOVATECH_NOME_COMPLETO:-Auditoria Combinações Lab}"
COD_START="${INOVATECH_CODIGO_INICIAL:-31}"
SKIP_SUBMIT="${INOVATECH_SKIP_SUBMIT:-0}"
SKIP_VERIFY="${INOVATECH_SKIP_VERIFY:-0}"

die() { echo "ERRO: $*" >&2; exit 1; }

[[ -d "${INV_ROOT}" ]] \
  || die "Diretório ${INV_ROOT} não encontrado. Rode o setup do laboratório."

command -v curl &>/dev/null || die "curl não encontrado (necessário para smoke HTTP)."

for cmd in inovatech-verify inovatech-versions \
           inovatech-preparar-entrega inovatech-submit; do
  command -v "${cmd}" &>/dev/null || die "Comando ${cmd} não está no PATH."
done

[[ "${COD_START}" =~ ^[0-9]{1,2}$ ]] \
  || die "INOVATECH_CODIGO_INICIAL inválido."
if (( 10#${COD_START} > 35 )); then
  die "INOVATECH_CODIGO_INICIAL deve ser ≤ 35 (são 6 códigos consecutivos até 40)."
fi

# shellcheck disable=SC1091
export NVM_DIR="${HOME}/.nvm"
if [[ -s "${NVM_DIR}/nvm.sh" ]]; then
  # shellcheck disable=SC1090
  source "${NVM_DIR}/nvm.sh"
  nvm use 2>/dev/null || true
fi

# Qualquer código HTTP (exceto falha de conexão) conta como “servidor vivo”.
http_any_local() {
  local url=$1
  local msg=${2:-GET}
  local code
  code="$(
    curl -s -o /dev/null -w "%{http_code}" \
      --connect-timeout 8 --max-time 15 "${url}" 2>/dev/null || echo "000"
  )"
  if [[ "${code}" == "000" ]] || [[ -z "${code}" ]]; then
    die "${msg} falhou (sem resposta): ${url}"
  fi
  echo "    [OK] ${msg} → HTTP ${code} (${url})"
}

kill_wait() {
  local pid=$1
  [[ -z "${pid}" ]] && return 0
  kill "${pid}" 2>/dev/null || true
  wait "${pid}" 2>/dev/null || true
}

# Libera porta se algo (ex.: filho do Vite) continuar escutando após o kill.
free_port() {
  local port=$1
  command -v lsof &>/dev/null || return 0
  local pids
  pids="$(lsof -ti ":${port}" 2>/dev/null || true)"
  [[ -z "${pids}" ]] && return 0
  # shellcheck disable=SC2086
  kill -9 ${pids} 2>/dev/null || true
}

combo_names() {
  local b=$1 f=$2
  local bn fn
  case "${b}" in
    1) bn="Django+DRF" ;;
    2) bn="FastAPI+SQLModel" ;;
    3) bn="Express+TypeORM" ;;
    *) die "backend inválido" ;;
  esac
  case "${f}" in
    1) fn="React+TS" ;;
    2) fn="Vanilla+TS" ;;
    *) die "frontend inválido" ;;
  esac
  echo "${bn} × ${fn}"
}

preparar_entrega() {
  local cod=$1 b=$2 f=$3
  local ent="${INV_ROOT}/entrega_${cod}"
  if [[ -d "${ent}" ]]; then
    printf '%s\n' "${cod}" "s" "${b}" "${f}"
  else
    printf '%s\n' "${cod}" "${b}" "${f}"
  fi
}

smoke_backend() {
  local dir=$1 kind=$2 port=$3
  local pid=""

  case "${kind}" in
    django)
      (
        cd "${dir}"
        .venv/bin/python manage.py migrate --noinput
        exec .venv/bin/python manage.py runserver "127.0.0.1:${port}"
      ) &
      pid=$!
      sleep 8
      http_any_local "http://127.0.0.1:${port}/" "Django runserver"
      ;;
    fastapi)
      (
        cd "${dir}"
        exec .venv/bin/python -m uvicorn main:app \
          --host 127.0.0.1 --port "${port}"
      ) &
      pid=$!
      sleep 8
      http_any_local "http://127.0.0.1:${port}/docs" "FastAPI /docs"
      ;;
    express)
      (
        cd "${dir}"
        export PORT="${port}"
        exec npm run dev
      ) &
      pid=$!
      sleep 12
      http_any_local "http://127.0.0.1:${port}/health" "Express /health"
      ;;
    *)
      die "tipo de backend desconhecido: ${kind}"
      ;;
  esac

  kill_wait "${pid}"
  free_port "${port}"
}

smoke_frontend() {
  local dir=$1 port=$2
  local pid=""

  (
    cd "${dir}"
    exec npm run dev -- --host 127.0.0.1 --port "${port}"
  ) &
  pid=$!
  sleep 10
  http_any_local "http://127.0.0.1:${port}/" "Vite dev server"
  kill_wait "${pid}"
  free_port "${port}"
}

map_back_folder() {
  case "$1" in
    1) echo "backend-django" ;;
    2) echo "backend-fastapi" ;;
    3) echo "backend-express" ;;
  esac
}

map_front_folder() {
  case "$1" in
    1) echo "frontend-react" ;;
    2) echo "frontend-vanilla" ;;
  esac
}

map_back_kind() {
  case "$1" in
    1) echo "django" ;;
    2) echo "fastapi" ;;
    3) echo "express" ;;
  esac
}

# ---------------------------------------------------------------------------
# 1–2. Verify e versions (uma vez)
# ---------------------------------------------------------------------------
if [[ "${SKIP_VERIFY}" != "1" ]]; then
  echo ""
  echo "========== inovatech-verify (global) =========="
  ( cd "${INV_ROOT}" && inovatech-verify )

  echo ""
  echo "========== inovatech-versions (global) =========="
  ( cd "${INV_ROOT}" && inovatech-versions "${INV_ROOT}" )
fi

# Combinações na mesma ordem do menu do preparar-entrega.
COMBOS=(
  "1 1"
  "1 2"
  "2 1"
  "2 2"
  "3 1"
  "3 2"
)

idx=0
for pair in "${COMBOS[@]}"; do
  read -r BACK_OPT FRONT_OPT <<< "${pair}"
  idx=$((idx + 1))

  COD="$(printf '%02d' "$((10#${COD_START} + idx - 1))")"
  ENTREGA_DIR="${INV_ROOT}/entrega_${COD}"
  BACK_DIR="${ENTREGA_DIR}/$(map_back_folder "${BACK_OPT}")"
  FRONT_DIR="${ENTREGA_DIR}/$(map_front_folder "${FRONT_OPT}")"
  BACK_KIND="$(map_back_kind "${BACK_OPT}")"

  # Portas fixas por índice para não colidir entre Python/Node/Vite.
  PY_PORT=$((9100 + idx))
  EX_PORT=$((9200 + idx))
  FE_PORT=$((9300 + idx))

  label="$(combo_names "${BACK_OPT}" "${FRONT_OPT}")"

  echo ""
  echo "######################################################################"
  echo "# Combinação ${idx}/6: ${label}"
  echo "# Código PP: ${COD}  |  entrega: ${ENTREGA_DIR}"
  echo "######################################################################"

  echo ""
  echo "---------- inovatech-preparar-entrega ----------"
  preparar_entrega "${COD}" "${BACK_OPT}" "${FRONT_OPT}" | (
    cd "${INV_ROOT}"
    inovatech-preparar-entrega
  )

  [[ -d "${ENTREGA_DIR}" ]] \
    || die "Pasta de entrega não criada: ${ENTREGA_DIR}"

  echo "Simulação combinada — ${label} — $(date -Iseconds)" \
    > "${ENTREGA_DIR}/SIMULACAO_COMBINACOES.txt"

  echo ""
  echo "---------- Smoke backend (${BACK_KIND}) ----------"
  case "${BACK_KIND}" in
    django|fastapi)
      smoke_backend "${BACK_DIR}" "${BACK_KIND}" "${PY_PORT}"
      ;;
    express)
      smoke_backend "${BACK_DIR}" "express" "${EX_PORT}"
      ;;
  esac

  echo ""
  echo "---------- Smoke frontend (Vite) ----------"
  smoke_frontend "${FRONT_DIR}" "${FE_PORT}"

  if [[ "${SKIP_SUBMIT}" != "1" ]]; then
    echo ""
    echo "---------- inovatech-submit ----------"
    printf '%s\n' "${COD}" "${NOME}" | (
      cd "${INV_ROOT}"
      inovatech-submit --dir "${ENTREGA_DIR}"
    )
  fi

  echo ""
  echo "[OK] Combinação ${idx}/6 concluída (${label})."
done

echo ""
echo "======================================================================"
echo " Todas as 6 combinações foram exercitadas com sucesso."
echo " Pastas: ${INV_ROOT}/entrega_$(printf '%02d' "$((10#${COD_START}))") …"
echo "         … até entrega_$(printf '%02d' "$((10#${COD_START} + 5))")"
echo "======================================================================"
