#!/usr/bin/env bash
# =============================================================================
# INOVATECH – Simula o fluxo do candidato (teste de ponta a ponta)
#
# Ordem (como na orientação ao candidato):
#   1. inovatech-verify
#   2. inovatech-versions
#   3. inovatech-preparar-entrega (código PP, backend, frontend)
#   4. pequeno artefato na pasta de entrega
#   5. inovatech-submit (código PP + nome completo)
#
# Pré-requisitos:
#   • ~/inovatech com os cinco projetos base (após setup).
#   • Comandos inovatech-* instalados no PATH.
#
# Matriz completa (6 stacks + smoke HTTP local): ver
#   outros/testar_todas_combinacoes_lab.sh
#
# Variáveis opcionais (laboratório = ~/inovatech, como no preparar-entrega):
#   INOVATECH_ROOT          raiz do lab (default: ${HOME}/inovatech); ajusta
#                           HOME para o diretório pai se necessário.
#   INOVATECH_NVM_DIR       NVM_DIR (default: ~/.nvm antes do ajuste de HOME)
#   INOVATECH_CODIGO_PP     código 01–40 (default: 01)
#   INOVATECH_NOME_COMPLETO nome no comprovante (default abaixo)
#   INOVATECH_BACKEND_OPT   1=Django, 2=FastAPI, 3=Express (default: 1)
#   INOVATECH_FRONTEND_OPT  1=React, 2=Vanilla (default: 1)
#   INOVATECH_LIMPEZA_ENTREGA 1=remove entrega_## antes (default: 1; repetir teste)
# =============================================================================

set -euo pipefail

ORIG_HOME="${HOME}"
INV_ROOT="${INOVATECH_ROOT:-${HOME}/inovatech}"
if [[ "$(cd "${INV_ROOT}/.." && pwd)" != "$(cd "${ORIG_HOME}" && pwd)" ]]; then
  export HOME="$(cd "${INV_ROOT}/.." && pwd)"
fi
INV_ROOT="${HOME}/inovatech"
export NVM_DIR="${INOVATECH_NVM_DIR:-${ORIG_HOME}/.nvm}"
if [[ -s "${NVM_DIR}/nvm.sh" ]]; then
  # shellcheck disable=SC1090
  source "${NVM_DIR}/nvm.sh"
  nvm use 2>/dev/null || true
fi
COD_IN="${INOVATECH_CODIGO_PP:-01}"
NOME="${INOVATECH_NOME_COMPLETO:-Candidato Teste Integração}"
BACK_OPT="${INOVATECH_BACKEND_OPT:-1}"
FRONT_OPT="${INOVATECH_FRONTEND_OPT:-1}"
LIMPEZA="${INOVATECH_LIMPEZA_ENTREGA:-1}"

die() { echo "ERRO: $*" >&2; exit 1; }

[[ -d "${INV_ROOT}" ]] \
  || die "Diretório ${INV_ROOT} não encontrado." \
" Rode o setup do laboratório nesta máquina."

for cmd in inovatech-verify inovatech-versions \
           inovatech-preparar-entrega inovatech-submit; do
  command -v "${cmd}" &>/dev/null \
    || die "Comando ${cmd} não está no PATH."
done

[[ "${COD_IN}" =~ ^[0-9]{1,2}$ ]] \
  || die "INOVATECH_CODIGO_PP deve ser numérico (01–40)."
COD="$(printf '%02d' "$((10#${COD_IN}))")"

ENTREGA_DIR="${INV_ROOT}/entrega_${COD}"

if [[ "${LIMPEZA}" == "1" ]] && [[ -d "${ENTREGA_DIR}" ]]; then
  echo "[INFO] Removendo ${ENTREGA_DIR} (INOVATECH_LIMPEZA_ENTREGA=1)."
  rm -rf "${ENTREGA_DIR}"
fi

echo ""
echo "========== 1/5  inovatech-verify =========="
(
  cd "${INV_ROOT}"
  inovatech-verify
)

echo ""
echo "========== 2/5  inovatech-versions =========="
(
  cd "${INV_ROOT}"
  inovatech-versions "${INV_ROOT}"
)

echo ""
echo "========== 3/5  inovatech-preparar-entrega =========="
# Prompts: código PP | [s/N se pasta já existir] | backend | frontend
if [[ -d "${ENTREGA_DIR}" ]]; then
  PREP_LINES="$(printf '%s\n' "${COD}" "s" "${BACK_OPT}" "${FRONT_OPT}")"
else
  PREP_LINES="$(printf '%s\n' "${COD}" "${BACK_OPT}" "${FRONT_OPT}")"
fi
echo "${PREP_LINES}" | (
  cd "${INV_ROOT}"
  inovatech-preparar-entrega
)

[[ -d "${ENTREGA_DIR}" ]] \
  || die "Pasta de entrega não foi criada: ${ENTREGA_DIR}"

echo ""
echo "========== 4/5  artefato simples na entrega =========="
echo "Simulação fluxo candidato — $(date -Iseconds)" \
  > "${ENTREGA_DIR}/SIMULACAO_CANDIDATO.txt"

echo ""
echo "========== 5/5  inovatech-submit =========="
# --dir evita erro quando há mais de uma entrega_## (ou entrega legada) em ~/inovatech.
printf '%s\n' "${COD}" "${NOME}" | (
  cd "${INV_ROOT}"
  inovatech-submit --dir "${ENTREGA_DIR}"
)

echo ""
echo "[OK] Fluxo simulado até inovatech-submit."
echo "     Entrega: ${ENTREGA_DIR}"
