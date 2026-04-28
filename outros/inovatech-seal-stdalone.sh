#!/usr/bin/env bash
# =============================================================================
# INOVATECH – Selagem Oficial dos Projetos Base
# Executado pela COORDENAÇÃO antes do início da prova
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[AVISO]${RESET} $*"; }
error()   { echo -e "${RED}[ERRO]${RESET}  $*"; exit 1; }
header()  { echo -e "\n${BOLD}${CYAN}======================================${RESET}"; \
            echo -e "${BOLD}${CYAN}  $*${RESET}"; \
            echo -e "${BOLD}${CYAN}======================================${RESET}\n"; }

sha256() {
  if command -v sha256sum &>/dev/null; then
    sha256sum "$@"
  else
    shasum -a 256 "$@"
  fi
}

BASE_DIR="$(pwd)"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir) BASE_DIR="$2"; shift 2 ;;
    *) error "Argumento desconhecido: $1" ;;
  esac
done

[ -d "${BASE_DIR}" ] || error "Diretório não encontrado: ${BASE_DIR}"

SEAL_DIR="${BASE_DIR}/.seal"
if [ -f "${SEAL_DIR}/hash_publico.txt" ]; then
  error "Selagem já foi concluída (existe ${SEAL_DIR}/hash_publico.txt)." \
" Não reexecute no ambiente de prova. Reinstale o ambiente (setup) apague" \
" a pasta .seal/ com cautela."
fi

TIMESTAMP=$(date '+%Y-%m-%dT%H:%M:%S')
DATESTAMP=$(date '+%Y%m%d_%H%M%S')
MANIFEST_FILE="${SEAL_DIR}/manifesto_${DATESTAMP}.txt"
HASH_FILE="${SEAL_DIR}/hash_publico.txt"

mkdir -p "${SEAL_DIR}"

PROJECT_DIRS=(
  "backend-django"
  "backend-fastapi"
  "backend-express"
  "frontend-vanilla"
  "frontend-react"
)

header "INOVATECH – Selagem dos Projetos Base"
info "Diretório base : ${BASE_DIR}"
info "Data/Hora      : ${TIMESTAMP}"
echo ""

info "Verificando projetos base..."
for proj in "${PROJECT_DIRS[@]}"; do
  dir="${BASE_DIR}/${proj}"
  if [ -d "${dir}" ]; then
    success "  ${proj}/"
  else
    error "Projeto não encontrado: ${dir}"
  fi
done
echo ""

list_files() {
  local dir="$1"
  find "${dir}" -type f \
    ! -path "*/.venv/*" \
    ! -path "*/node_modules/*" \
    ! -path "*/__pycache__/*" \
    ! -path "*/.git/*" \
    ! -path "*/*.pyc" \
    ! -path "*/*.pyo" \
    ! -path "*/dist/*" \
    ! -path "*/.seal/*" \
    ! -name "*.log" \
    ! -name ".DS_Store" \
    ! -name "*.sqlite3" \
    ! -name "*.db" \
    ! -name "package-lock.json" \
    | LC_ALL=C sort
}

info "Gerando manifesto de hashes por arquivo..."
echo ""

{
  echo "# ============================================="
  echo "# INOVATECH – Manifesto de Integridade"
  echo "# Gerado em  : ${TIMESTAMP}"
  echo "# Algoritmo  : SHA-256"
  echo "# Hash raiz  : SHA-256 da concatenação ordenada de"
  echo "#   caminho_relativo<TAB>hash_arquivo (LC_ALL=C)"
  echo "# ============================================="
  echo ""
} > "${MANIFEST_FILE}"

HASH_ENTRIES_FILE=$(mktemp)
trap 'rm -f "${HASH_ENTRIES_FILE}"' EXIT

for proj in "${PROJECT_DIRS[@]}"; do
  echo "## Projeto: ${proj}" >> "${MANIFEST_FILE}"
  echo "" >> "${MANIFEST_FILE}"
  file_count=0
  while IFS= read -r relpath; do
    file_hash=$(sha256 "${BASE_DIR}/${relpath}" | awk '{print $1}')
    printf "%-64s  %s\n" \
      "${file_hash}" "${relpath}" >> "${MANIFEST_FILE}"
    printf '%s\t%s\n' "${relpath}" "${file_hash}" >> "${HASH_ENTRIES_FILE}"
    file_count=$((file_count + 1))
  done < <( cd "${BASE_DIR}" && list_files "${proj}" )
  echo "" >> "${MANIFEST_FILE}"
  success "  ${proj}/ → ${file_count} arquivos"
done

TOTAL=$(wc -l < "${HASH_ENTRIES_FILE}" | tr -d ' ')
info "Total de arquivos hasheados: ${TOTAL}"

ROOT_HASH=$(
  LC_ALL=C sort "${HASH_ENTRIES_FILE}" \
    | sha256 | awk '{print $1}'
)

{
  echo ""
  echo "# HASH RAIZ"
  echo "${ROOT_HASH}"
} >> "${MANIFEST_FILE}"

{
  echo "=============================================================="
  echo "  INOVATECH – Hash Oficial dos Projetos Base"
  echo "  Edital 30/2026 – GAB/REI/IFPI"
  echo "=============================================================="
  echo ""
  echo "  Data/Hora da Selagem : ${TIMESTAMP}"
  echo "  Algoritmo            : SHA-256 (hash raiz)"
  echo ""
  echo "  HASH PÚBLICO OFICIAL"
  echo "  ────────────────────────────────────────────────────────────"
  echo "  ${ROOT_HASH}"
  echo "  ────────────────────────────────────────────────────────────"
  echo ""
  echo "  Manifesto detalhado : ${MANIFEST_FILE}"
  echo "=============================================================="
} > "${HASH_FILE}"
cp "${HASH_FILE}" "${SEAL_DIR}/hash_publico_${DATESTAMP}.txt"

header "SELAGEM CONCLUÍDA"
cat "${HASH_FILE}"

echo ""
warn "Divulgue o HASH PÚBLICO OFICIAL aos candidatos antes do início da prova."
success "Selagem finalizada."
