#!/usr/bin/env bash
# =============================================================================
# INOVATECH – Patch rápido de laboratório já instalado
#
# Atualiza só:
#   • logos IFPI + Copa na raiz ~/inovatech/ e em frontend-react|vanilla/public
#   • /usr/local/bin/inovatech-versions (cor BOLD/CYAN/RESET)
#   • /usr/local/bin/inovatech-preparar-entrega (sync de logos pós-rsync)
#
# Não altera pastas entrega_* nem projetos backend.
#
# Uso:
#   cd ~/inovatech && bash /caminho/clone/patch_inovatech_lab.sh
#   curl -fsSL https://raw.githubusercontent.com/RomuloBarrosPI/inovatech-lab-prep/main/patch_inovatech_lab.sh | bash
#
# Opcional:
#   INOVATECH_ROOT=/outro/lab
#   PATCH_SETUP_SRC=./setup_inovatech.sh   (evita baixar do GitHub)
#   PATCH_BIN_DIR="${HOME}/.local/bin"      (instala comandos sem sudo; coloque no PATH)
# =============================================================================

set -euo pipefail

GITHUB_RAW="https://raw.githubusercontent.com/RomuloBarrosPI/inovatech-lab-prep/main"
INV_ROOT="${INOVATECH_ROOT:-${HOME}/inovatech}"

say() { echo "[patch-inovatech] $*"; }
die() { echo "[patch-inovatech] ERRO: $*" >&2; exit 1; }

if [[ ! -d "${INV_ROOT}" ]]; then
  die "Diretório ${INV_ROOT} não existe (defina INOVATECH_ROOT se o lab não está em ~/inovatech)."
fi

if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
  SCRIPT_DIR=""
fi

SETUP_TMP="$(mktemp)"
trap 'rm -f "${SETUP_TMP}"' EXIT

obtain_setup() {
  if [[ -n "${PATCH_SETUP_SRC:-}" && -f "${PATCH_SETUP_SRC}" ]]; then
    cp "${PATCH_SETUP_SRC}" "${SETUP_TMP}"
    say "Usando setup em ${PATCH_SETUP_SRC}"
    return
  fi
  if [[ -f "${PWD}/setup_inovatech.sh" ]]; then
    cp "${PWD}/setup_inovatech.sh" "${SETUP_TMP}"
    say "Usando ./setup_inovatech.sh (cwd)"
    return
  fi
  if [[ -n "${SCRIPT_DIR}" && -f "${SCRIPT_DIR}/setup_inovatech.sh" ]]; then
    cp "${SCRIPT_DIR}/setup_inovatech.sh" "${SETUP_TMP}"
    say "Usando ${SCRIPT_DIR}/setup_inovatech.sh"
    return
  fi
  say "Baixando setup_inovatech.sh do GitHub..."
  if command -v curl &>/dev/null; then
    curl -fsSL "${GITHUB_RAW}/setup_inovatech.sh" -o "${SETUP_TMP}"
  elif command -v wget &>/dev/null; then
    wget -q "${GITHUB_RAW}/setup_inovatech.sh" -O "${SETUP_TMP}"
  else
    die "curl/wget ausentes e setup local não encontrado."
  fi
}

extract_versions_bin() {
  awk '
    /^cat > \/tmp\/inovatech-versions << .VERSIONS_SCRIPT.$/ {skip=1; next}
    skip && /^VERSIONS_SCRIPT$/ {exit}
    skip {print}
  ' "${SETUP_TMP}" > /tmp/inovatech-versions
}

extract_preparar_bin() {
  awk '
    /^cat > \/tmp\/inovatech-preparar-entrega << .PREP_SCRIPT.$/ {skip=1; next}
    skip && /^PREP_SCRIPT$/ {exit}
    skip {print}
  ' "${SETUP_TMP}" > /tmp/inovatech-preparar-entrega
}

install_bin() {
  local f="$1"
  local name dest dest_dir
  name="$(basename "${f}")"
  dest_dir="${PATCH_BIN_DIR:-/usr/local/bin}"
  dest="${dest_dir}/${name}"
  chmod +x "${f}"
  if mkdir -p "${dest_dir}" 2>/dev/null && [[ -w "${dest_dir}" ]]; then
    cp "${f}" "${dest}"
    chmod +x "${dest}"
    say "Instalado ${dest}"
    return
  fi
  if [[ "$(id -u)" -eq 0 ]]; then
    mkdir -p "${dest_dir}"
    cp "${f}" "${dest}"
    chmod +x "${dest}"
    say "Instalado ${dest}"
    return
  fi
  sudo mkdir -p "${dest_dir}"
  sudo cp "${f}" "${dest}"
  sudo chmod +x "${dest}"
  say "Instalado ${dest}"
}

sync_logos_root() {
  FETCH=""
  if command -v curl &>/dev/null; then
    FETCH=curl
  elif command -v wget &>/dev/null; then
    FETCH=wget
  fi

  for ASSET in logo-inovatech.png logo-copa-inovatech.png \
               logo-copa-inovatech-preto.png; do
    if [[ -f "${INV_ROOT}/${ASSET}" ]]; then
      continue
    fi
    [[ -n "${FETCH}" ]] || {
      say "Sem rede/curl/wget; não foi possível obter ${ASSET}."
      continue
    }
    say "Baixando ${ASSET}..."
    if [[ "${FETCH}" == curl ]]; then
      curl -fsSL "${GITHUB_RAW}/${ASSET}" \
        -o "${INV_ROOT}/${ASSET}" || true
    else
      wget -q "${GITHUB_RAW}/${ASSET}" \
        -O "${INV_ROOT}/${ASSET}" || true
    fi
    [[ -f "${INV_ROOT}/${ASSET}" ]] \
      || say "Falha ao baixar ${ASSET} (confira se existe em main no GitHub)."
  done
}

copy_logos_to_base_frontends() {
  local pub brand
  for sub in frontend-react frontend-vanilla; do
    if [[ ! -d "${INV_ROOT}/${sub}" ]]; then
      continue
    fi
    pub="${INV_ROOT}/${sub}/public"
    mkdir -p "${pub}"
    for brand in logo-inovatech.png logo-copa-inovatech.png \
                 logo-copa-inovatech-preto.png; do
      if [[ -f "${INV_ROOT}/${brand}" ]]; then
        cp "${INV_ROOT}/${brand}" "${pub}/${brand}"
      fi
    done
    say "Logos atualizados em ${pub}/"
  done

  if [[ -d "${INV_ROOT}/figurinhas" ]]; then
    for sub in frontend-react frontend-vanilla; do
      if [[ ! -d "${INV_ROOT}/${sub}" ]]; then
        continue
      fi
      mkdir -p "${INV_ROOT}/${sub}/public/assets/figurinhas"
      cp -r "${INV_ROOT}/figurinhas/"* \
        "${INV_ROOT}/${sub}/public/assets/figurinhas/" 2>/dev/null \
        || true
    done
    say "Figurinhas sincronizadas em public/assets/figurinhas (projetos base)."
  fi
}

say "Raiz do laboratório: ${INV_ROOT}"
say "Pastas entrega_* não serão modificadas."

obtain_setup

extract_versions_bin
[[ -s /tmp/inovatech-versions ]] \
  || die "Extração de inovatech-versions falhou (setup_inovatech.sh incompatível?)."
extract_preparar_bin
[[ -s /tmp/inovatech-preparar-entrega ]] \
  || die "Extração de inovatech-preparar-entrega falhou."

install_bin /tmp/inovatech-versions
install_bin /tmp/inovatech-preparar-entrega

sync_logos_root
copy_logos_to_base_frontends

say "Concluído. Teste: inovatech-versions ${INV_ROOT}"
