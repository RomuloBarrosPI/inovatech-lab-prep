#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIRS=(
  "backend-django"
  "backend-fastapi"
  "backend-express"
  "frontend-vanilla"
  "frontend-react"
)

BASE_DIR="${HOME}/inovatech"
SAMPLE_LINES=10

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)
      BASE_DIR="$2"
      shift 2
      ;;
    --sample-lines)
      SAMPLE_LINES="$2"
      shift 2
      ;;
    *)
      echo "Argumento desconhecido: $1" >&2
      echo "Uso: bash inovatech_hash_diagnose.sh [--dir CAMINHO]" >&2
      echo "                               [--sample-lines N]" >&2
      exit 1
      ;;
  esac
done

if [[ ! -d "${BASE_DIR}" ]]; then
  echo "ERRO: diretório não encontrado: ${BASE_DIR}" >&2
  exit 1
fi

sha256_line() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum
  else
    shasum -a 256
  fi
}

sha256_file() {
  local file_path="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${file_path}" | awk '{print $1}'
  else
    shasum -a 256 "${file_path}" | awk '{print $1}'
  fi
}

build_entries() {
  local rel_path=""
  local hash=""
  local proj=""

  for proj in "${PROJECT_DIRS[@]}"; do
    if [[ ! -d "${BASE_DIR}/${proj}" ]]; then
      echo "ERRO: projeto não encontrado: ${BASE_DIR}/${proj}" >&2
      return 1
    fi

    while IFS= read -r rel_path; do
      hash="$(sha256_file "${BASE_DIR}/${rel_path}")"
      printf '%s\t%s\n' "${rel_path}" "${hash}"
    done < <(
      cd "${BASE_DIR}" && find "${proj}" -type f \
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
    )
  done
}

verify_path="$(command -v inovatech-verify 2>/dev/null || true)"
verify_checksum="N/A"
if [[ -n "${verify_path}" && -f "${verify_path}" ]]; then
  verify_checksum="$(sha256_file "${verify_path}")"
fi

sort_info="$(
  (sort --version 2>/dev/null | awk 'NR==1') || true
)"
if [[ -z "${sort_info}" ]]; then
  sort_info="$(command -v sort)"
fi

libc_info="$(
  (ldd --version 2>/dev/null | awk 'NR==1') || true
)"
if [[ -z "${libc_info}" ]]; then
  libc_info="N/A"
fi

verify_hash="N/A"
if [[ -n "${verify_path}" ]]; then
  verify_hash="$(
    inovatech-verify --dir "${BASE_DIR}" 2>/dev/null \
      | awk '/^[[:space:]]*[0-9a-f]{64}[[:space:]]*$/ {print $1; exit}'
  )"
  if [[ -z "${verify_hash}" ]]; then
    verify_hash="N/A"
  fi
fi

canon_hash="$(
  build_entries \
    | LC_ALL=C sort \
    | sha256_line \
    | awk '{print $1}'
)"

total_files="$(
  build_entries | wc -l | tr -d ' '
)"

status="DIFF"
if [[ "${verify_hash}" == "${canon_hash}" ]]; then
  status="OK"
fi
if [[ "${verify_hash}" == "N/A" ]]; then
  status="N/A (inovatech-verify indisponível)"
fi

echo "=== INOVATECH HASH DIAGNOSTIC ==="
echo "BASE_DIR=${BASE_DIR}"
echo "VERIFY_PATH=${verify_path:-N/A}"
echo "VERIFY_BIN_SHA256=${verify_checksum}"
echo "LANG=${LANG:-}"
echo "LC_ALL=${LC_ALL:-}"
echo "LC_COLLATE=${LC_COLLATE:-}"
echo "SORT_INFO=${sort_info}"
echo "LIBC_INFO=${libc_info}"
echo "TOTAL_FILES=${total_files}"
echo "VERIFY_HASH=${verify_hash}"
echo "CANON_INPUT_SHA=${canon_hash}"
echo "COMPARE_STATUS=${status}"
echo "SAMPLE_ENTRIES_HEAD=${SAMPLE_LINES}"
build_entries | LC_ALL=C sort | head -n "${SAMPLE_LINES}"
