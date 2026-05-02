#!/usr/bin/env bash
# =============================================================================
# INOVATECH – Enviar entrega por HTTPS (multipart) — COMISSÃO, pós-prova
#
# Modalidade laboratório: nome_candidato + codigo_posicao (+ edicao_pk se
# necessário). Modalidade token: --token (Bearer). Ver ENTREGA-PROVA-PRATICA-API.
#
# Config opcional: /etc/inovatech/entrega.env (export INOVATECH_*)
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[AVISO]${RESET} $*"; }
error()   { echo -e "${RED}[ERRO]${RESET}  $*"; exit 1; }

if [[ -r /etc/inovatech/entrega.env ]]; then
  # shellcheck source=/dev/null
  source /etc/inovatech/entrega.env
fi

DEFAULT_URL="https://inovatech.ifpi.edu.br/api/entrega-prova-pratica/"
MAX_BYTES=$((80 * 1024 * 1024))

ENTREGA_DIR=""
URL="${INOVATECH_ENTREGA_URL:-$DEFAULT_URL}"
SECRET="${INOVATECH_ENTREGA_SECRET:-}"
EDICAO_PK="${INOVATECH_EDICAO_PK:-}"
NOME=""
CODIGO=""
TOKEN=""
SEM_COMPROVANTE=0
FORCE=0
INV_ROOT="${INOVATECH_ROOT:-${HOME}/inovatech}"

usage() {
  sed -n '1,80p' << 'USAGE'
Uso: inovatech-enviar-entrega [opções]

  Comissão: após liberar a internet, envia a pasta de entrega (ZIP) à API.

Modo laboratório (padrão):
  --nome "nome do candidato"
  --codigo N   (posição na classificação geral, 01–40 típ.)
  --edicao-pk N   (se o servidor não tiver PROVA_PRATICA_ENTREGA_EDICAO_PK)

Modo token:
  --token BEARER   (não usa --nome / --codigo)

Geral:
  --dir /caminho/entrega_##   (senão: deteta em $INOVATECH_ROOT ou ~/inovatech)
  --url URL          (padrão: produção inovatech.ifpi.edu.br)
  --secret VALOR     → cabeçalho X-Entrega-Prova-Pratica-Secret
  --sem-comprovante  exclui .comprovante/ do ZIP (alinha ao manifesto hasheado)
  --force            envia mesmo se ZIP > 80 MiB

Variáveis de ambiente: INOVATECH_ENTREGA_URL, INOVATECH_ENTREGA_SECRET,
  INOVATECH_EDICAO_PK, INOVATECH_ROOT

Arquivo opcional: /etc/inovatech/entrega.env
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)            ENTREGA_DIR="$2"; shift 2 ;;
    --url)            URL="$2"; shift 2 ;;
    --secret)         SECRET="$2"; shift 2 ;;
    --edicao-pk)      EDICAO_PK="$2"; shift 2 ;;
    --nome)           NOME="$2"; shift 2 ;;
    --codigo)         CODIGO="$2"; shift 2 ;;
    --token)          TOKEN="$2"; shift 2 ;;
    --sem-comprovante) SEM_COMPROVANTE=1; shift ;;
    --force)          FORCE=1; shift ;;
    -h|--help)        usage; exit 0 ;;
    *) error "Opção desconhecida: $1 (use --help)" ;;
  esac
done

command -v curl &>/dev/null || error "curl não encontrado."
command -v zip &>/dev/null || error "Comando 'zip' não encontrado. Instale: sudo apt install zip"

# ---- Detetar pasta de entrega (igual inovatech-submit, base INOVATECH_ROOT) ----
if [[ -z "${ENTREGA_DIR}" ]]; then
  cands=()
  if [[ -d "${INV_ROOT}/entrega" ]]; then
    cands+=("${INV_ROOT}/entrega")
  fi
  shopt -s nullglob
  for d in "${INV_ROOT}"/entrega_[0-9][0-9]; do
    [[ -d "$d" ]] || continue
    bname=$(basename "$d")
    code=${bname#entrega_}
    if [[ "${code}" =~ ^(0[1-9]|[1-3][0-9]|40)$ ]]; then
      cands+=("$d")
    fi
  done
  shopt -u nullglob
  nc=${#cands[@]}
  if [[ "${nc}" -eq 0 ]]; then
    error "Pasta de entrega não encontrada em ${INV_ROOT}. Use" \
          " --dir /caminho ou defina/há entrega_##"
  elif [[ "${nc}" -gt 1 ]]; then
    error "Várias pastas de entrega em ${INV_ROOT}. Especifique:" \
          " inovatech-enviar-entrega --dir /caminho"
  else
    ENTREGA_DIR="${cands[0]}"
  fi
fi

[[ -d "${ENTREGA_DIR}" ]] || error "Pasta não encontrada: ${ENTREGA_DIR}"
ENTREGA_ABS="$(cd "${ENTREGA_DIR}" && pwd)"

# ---- Modo token vs laboratório + prompts se faltar ----
LAB=1
if [[ -n "${TOKEN}" ]]; then
  LAB=0
elif [[ -z "${NOME}" || -z "${CODIGO}" ]]; then
  echo -e "${BOLD}Identificação (modo laboratório)${RESET}"
  [[ -z "${NOME}" ]] && read -rp "  nome_candidato: " NOME
  [[ -z "${CODIGO}" ]] && read -rp "  codigo_posicao (01–40 típ.): " CODIGO
fi

if [[ "${LAB}" -eq 1 ]]; then
  [[ -n "${NOME// }" ]] || error "nome_candidato é obrigatório."
  [[ -n "${CODIGO// }" ]] || error "codigo_posicao é obrigatório."
  # Normalização leve para nome do arquivo
  CODIGO_TR=$(echo "${CODIGO}" | xargs)
  if [[ "${CODIGO_TR}" =~ ^[0-9]+$ ]]; then
    CODZIP=$(printf '%02d' "$((10#${CODIGO_TR}))")
  else
    CODZIP="XX"
  fi
else
  CODZIP=""
fi

DATESTAMP=$(date '+%Y%m%d_%H%M%S')
TMPZIP="$(mktemp /tmp/inovatech_entrega_XXXXXX.zip)"
rm -f "${TMPZIP}" # zip falha com "Zip file structure invalid" se o arquivo existir e tiver 0 bytes
BODY="$(mktemp)"
trap 'rm -f "${TMPZIP}" "${BODY}" 2>/dev/null' EXIT

echo ""
echo -e "${BOLD}${CYAN}INOVATECH – Envio HTTPS (comissão – pós-prova)${RESET}"
echo ""

info "Empacotando: ${ENTREGA_ABS}"

build_zip() {
  if [[ "${SEM_COMPROVANTE}" -eq 1 ]]; then
    (
      cd "${ENTREGA_ABS}" || exit 1
      find . -type f \
        ! -path '*/.venv/*' \
        ! -path '*/node_modules/*' \
        ! -path '*/__pycache__/*' \
        ! -path '*/.git/*' \
        ! -name '*.pyc' \
        ! -name '*.pyo' \
        ! -path '*/dist/*' \
        ! -path '*/.comprovante/*' \
        ! -name '*.log' \
        ! -name '.DS_Store' \
        ! -name '*.sqlite3' \
        ! -name '*.db' \
        ! -name 'package-lock.json' \
        | LC_ALL=C sort \
        | zip -q "${TMPZIP}" -@
    )
  else
    (
      cd "${ENTREGA_ABS}" || exit 1
      find . -type f \
        ! -path '*/.venv/*' \
        ! -path '*/node_modules/*' \
        ! -path '*/__pycache__/*' \
        ! -path '*/.git/*' \
        ! -name '*.pyc' \
        ! -name '*.pyo' \
        ! -path '*/dist/*' \
        ! -name '*.log' \
        ! -name '.DS_Store' \
        ! -name '*.sqlite3' \
        ! -name '*.db' \
        ! -name 'package-lock.json' \
        | LC_ALL=C sort \
        | zip -q "${TMPZIP}" -@
    )
  fi
}

build_zip

ZS=$(stat -c%s "${TMPZIP}" 2>/dev/null || stat -f%z "${TMPZIP}" 2>/dev/null || echo 0)
if [[ "${ZS}" -eq 0 ]]; then
  error "ZIP vazio — nenhum ficheiro após filtros?"
fi

if [[ "${ZS}" -gt "${MAX_BYTES}" ]] && [[ "${FORCE}" -eq 0 ]]; then
  error "ZIP com ${ZS} bytes excede 80 MiB. Reduza a pasta ou use --force" \
        " (ou confirme Nginx/backend)."
fi
if [[ "${ZS}" -gt "${MAX_BYTES}" ]]; then
  warn "ZIP > 80 MiB — envio pode falhar com 413."
fi

read_sig=$(head -c 2 "${TMPZIP}" || true)
if [[ "${read_sig}" != $'PK' ]]; then
  error "Ficheiro gerado não parece ZIP (assinatura PK ausente)."
fi

ZIPNAME="inovatech_entrega_${CODZIP:-na}_${DATESTAMP}.zip"
info "ZIP: ${ZS} bytes → ${ZIPNAME}"

# ---- Backup no Pendrive ----
info "Tentando realizar backup do ZIP no pendrive..."
BACKUP_DONE=0
shopt -s nullglob
for pd in /media/*/*; do
  if [[ -d "$pd" ]]; then
    BKP_DIR="${pd}/inovatech_backups"
    if mkdir -p "${BKP_DIR}" 2>/dev/null; then
      SAFE_NOME=$(echo "${NOME}" | sed -E 's/[^a-zA-Z0-9]+/_/g')
      BKP_FILE="${BKP_DIR}/entrega_${CODIGO}_${SAFE_NOME}_${DATESTAMP}.zip"
      if cp "${TMPZIP}" "${BKP_FILE}" 2>/dev/null; then
        success "Backup salvo em: ${BKP_FILE}"
        BACKUP_DONE=1
        break
      fi
    fi
  fi
done
shopt -u nullglob

if [[ "${BACKUP_DONE}" -eq 0 ]]; then
  warn "Não foi possível salvar o backup em um pendrive (nenhum encontrado ou sem permissão)."
fi

if [[ "${LAB}" -eq 1 ]]; then
  NOME="$(echo "${NOME}" | xargs)"
  CODIGO="$(echo "${CODIGO}" | xargs)"
fi

# ---- CURL ----
HEADER_ARGS=()
if [[ -n "${SECRET}" ]]; then
  HEADER_ARGS+=( -H "X-Entrega-Prova-Pratica-Secret: ${SECRET}" )
fi

MULTI=( -sS \
  --max-time 600 \
  --retry 3 \
  --retry-all-errors )

if [[ "${LAB}" -eq 1 ]]; then
  MULTI+=(
    -F "nome_candidato=${NOME}"
    -F "codigo_posicao=${CODIGO}"
    -F "arquivo=@${TMPZIP};filename=${ZIPNAME};type=application/zip"
  )
  [[ -n "${EDICAO_PK}" ]] && MULTI+=( -F "edicao_pk=${EDICAO_PK}" )
else
  MULTI+=(
    -H "Authorization: Bearer ${TOKEN}"
    -F "arquivo=@${TMPZIP};filename=${ZIPNAME};type=application/zip"
  )
fi

HTTP=$(curl "${MULTI[@]}" "${HEADER_ARGS[@]}" -o "${BODY}" \
  -w '%{http_code}' "${URL}")

echo ""
echo -e "${BOLD}Resposta HTTP: ${HTTP}${RESET}"
cat "${BODY}"
echo ""

if [[ "${HTTP}" != "200" ]]; then
  error "Upload falhou (HTTP ${HTTP}). Ver JSON acima."
fi

OK=0
if command -v jq &>/dev/null; then
  jq -e '.ok == true' "${BODY}" &>/dev/null && OK=1 || true
else
  if python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get('ok') is True else 1)" "${BODY}" 2>/dev/null; then OK=1; fi
fi
if [[ "${OK}" -eq 1 ]]; then
  success "Entrega registada pela API."
else
  error "HTTP 200 mas campo ok não é true — conferir JSON acima."
fi
