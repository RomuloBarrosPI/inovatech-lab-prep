#!/usr/bin/env bash
# =============================================================================
# INOVATECH – Gera pacote .tar.gz para atualização offline do laboratório
#
# Pré-requisito: árvore em ~/inovatech já refletindo o setup atual (sem selagem
#   obrigatória no pacote — .seal/ é excluído). O hash esperado é o mesmo que
#   inovatech-verify calcula sobre os cinco projetos base.
#
# Uso:
#   bash outros/gerar_pacote_atualizacao_offline.sh \
#     --output /media/pendrive/inovatech-offline-$(date +%Y%m%d).tar.gz
#
# Opções:
#   --source-root DIR   origem (default: ~/inovatech)
#   --setup-src PATH    copy deste setup (default: diretório do repo)
# =============================================================================

set -euo pipefail

SOURCE_ROOT="${HOME}/inovatech"
OUTPUT=""
SETUP_SRC=""

die() { echo "[gerar-pacote-offline] ERRO: $*" >&2; exit 1; }
say() { echo "[gerar-pacote-offline] $*"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-root) SOURCE_ROOT="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    --setup-src) SETUP_SRC="$2"; shift 2 ;;
    *) die "Argumento desconhecido: $1" ;;
  esac
done

[[ -n "${OUTPUT}" ]] || die "Informe --output CAMINHO.tar.gz"

[[ -d "${SOURCE_ROOT}" ]] || die "Diretório fonte inexistente: ${SOURCE_ROOT}"

for proj in backend-django backend-fastapi backend-express \
            frontend-vanilla frontend-react; do
  [[ -d "${SOURCE_ROOT}/${proj}" ]] \
    || die "Projeto ausente em ${SOURCE_ROOT}: ${proj}/"
done

SCRIPT_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

resolve_setup() {
  if [[ -n "${SETUP_SRC}" ]]; then
    [[ -f "${SETUP_SRC}" ]] || die "setup não encontrado: ${SETUP_SRC}"
    echo "${SETUP_SRC}"
    return
  fi
  local repo_root
  repo_root="$(cd "${SCRIPT_DIR}/.." && pwd)"
  if [[ -f "${repo_root}/setup_inovatech.sh" ]]; then
    echo "${repo_root}/setup_inovatech.sh"
    return
  fi
  die "Não encontrei setup_inovatech.sh; use --setup-src."
}

SETUP_FILE="$(resolve_setup)"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

BUNDLE="${WORK}/inovatech-offline-bundle"
mkdir -p "${BUNDLE}/inovatech"

say "Sincronizando ${SOURCE_ROOT}/ → ${BUNDLE}/inovatech/ ..."
rsync -a \
  --delete \
  --exclude '.seal/' \
  --exclude 'entrega/' \
  --exclude 'entrega_[0-9][0-9]/' \
  "${SOURCE_ROOT}/" "${BUNDLE}/inovatech/"

cp "${SETUP_FILE}" "${BUNDLE}/setup_inovatech.sh"

if ! command -v inovatech-verify &>/dev/null; then
  die "inovatech-verify não está no PATH (instale os binários do setup antes)."
fi

VERIFY_HASH="$(
  inovatech-verify --dir "${BUNDLE}/inovatech" 2>/dev/null \
    | awk '/^[[:space:]]*[0-9a-f]{64}[[:space:]]*$/ {print $1; exit}'
)"
[[ -n "${VERIFY_HASH}" ]] || die "Não foi possível obter hash de inovatech-verify."

{
  echo "PACK_DATE=$(date -Iseconds)"
  echo "SOURCE_ROOT=${SOURCE_ROOT}"
  echo "EXPECTED_VERIFY_HASH=${VERIFY_HASH}"
} > "${BUNDLE}/MANIFEST.txt"

say "EXPECTED_VERIFY_HASH=${VERIFY_HASH}"

OUT_DIR="$(dirname "${OUTPUT}")"
mkdir -p "${OUT_DIR}"

tar -czf "${OUTPUT}" -C "${WORK}" "inovatech-offline-bundle"

say "Pacote gerado: ${OUTPUT}"
say "Transfira o arquivo aos laboratórios e rode:"
say "  bash atualizar_inovatech_lab.sh --offline-bundle ${OUTPUT} --yes"
