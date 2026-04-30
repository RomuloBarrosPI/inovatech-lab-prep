#!/usr/bin/env bash
# =============================================================================
# INOVATECH – Atualizar laboratório para a versão atual do setup
#
# Modo online (padrão): baixa ou usa setup_inovatech.sh, força reset completo
# (recria os cinco projetos base, comandos inovatech-*), opcionalmente selagem.
#
# Modo offline: restaura árvore inovatech/ a partir de um pacote gerado por
#   outros/gerar_pacote_atualizacao_offline.sh, reinstala binários extraídos do
#   setup embutido no pacote e executa selagem + verify.
#
# Uso:
#   bash atualizar_inovatech_lab.sh [--yes] [--no-seal]
#       [--root DIR] [--setup-src CAMINHO] [--log-dir DIR]
#   bash atualizar_inovatech_lab.sh --offline-bundle PACOTE.tar.gz|DIR
#       [--yes] [--no-seal] [--root DIR] [--log-dir DIR]
#
# Variáveis:
#   INOVATECH_ASSUME_YES=1  equivalente a --yes
#   INOVATECH_GITHUB_RAW    base URL raw (default: repo main no GitHub)
# =============================================================================

set -euo pipefail

GITHUB_RAW_DEFAULT="https://raw.githubusercontent.com/RomuloBarrosPI/inovatech-lab-prep/main"
GITHUB_RAW="${INOVATECH_GITHUB_RAW:-${GITHUB_RAW_DEFAULT}}"

LAB_ROOT="${HOME}/inovatech"
LOG_DIR="${HOME}/inovatech_update_logs"
SETUP_SRC=""
OFFLINE_BUNDLE=""
ASSUME_YES="${INOVATECH_ASSUME_YES:-0}"
NO_SEAL="0"

say() { echo "[atualizar-inovatech] $*"; }
die() { echo "[atualizar-inovatech] ERRO: $*" >&2; exit 1; }

usage() {
  if [[ -f "${BASH_SOURCE[0]:-}" ]]; then
    sed -n '2,38p' "${BASH_SOURCE[0]}"
  else
    echo "Uso: atualizar_inovatech_lab.sh [--yes] [--no-seal]"
    echo "       [--root DIR] [--setup-src CAMINHO] [--log-dir DIR]"
    echo "       [--offline-bundle PACOTE.tar.gz|DIR]"
  fi
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) LAB_ROOT="$2"; shift 2 ;;
    --setup-src) SETUP_SRC="$2"; shift 2 ;;
    --log-dir) LOG_DIR="$2"; shift 2 ;;
    --offline-bundle) OFFLINE_BUNDLE="$2"; shift 2 ;;
    --yes) ASSUME_YES="1"; shift ;;
    --no-seal) NO_SEAL="1"; shift ;;
    -h|--help) usage ;;
    *) die "Argumento desconhecido: $1 (use --help)" ;;
  esac
done

mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/update_$(date '+%Y%m%d_%H%M%S').log"
exec > >(tee -a "${LOG_FILE}") 2>&1

say "Log: ${LOG_FILE}"

# inovatech-preparar-entrega usa ${HOME}/inovatech fixo.
normalize_lab_home() {
  local parent base
  parent="$(cd "$(dirname "${LAB_ROOT}")" && pwd)"
  base="$(basename "${LAB_ROOT}")"
  if [[ "${base}" != "inovatech" ]]; then
    die "O diretório final deve se chamar inovatech (recebido: ${LAB_ROOT})."
  fi
  if [[ "${parent}" != "${HOME}" ]]; then
    die "LAB_ROOT deve ser exatamente \${HOME}/inovatech para a prova." \
        " HOME=${HOME}, pai atual=${parent}"
  fi
}

normalize_lab_home

have_sudo() {
  if [[ "$(id -u)" -eq 0 ]]; then
    return 0
  fi
  if command -v sudo &>/dev/null && sudo -n true 2>/dev/null; then
    return 0
  fi
  return 1
}

ensure_sudo() {
  if [[ "$(id -u)" -eq 0 ]]; then
    return 0
  fi
  command -v sudo &>/dev/null || die "sudo não encontrado (necessário para" \
    " instalar comandos em /usr/local/bin)."
  sudo true
}

read_old_public_hash() {
  local hf="${LAB_ROOT}/.seal/hash_publico.txt"
  if [[ -f "${hf}" ]]; then
    grep -Eo '[0-9a-f]{64}' "${hf}" | head -n1 || true
  fi
}

confirm_reset() {
  if [[ "${ASSUME_YES}" == "1" ]]; then
    return 0
  fi
  echo ""
  warn_msg="Isto apaga .seal/, os cinco projetos base, entrega/ e entrega_##/"
  warn_msg="${warn_msg} em ${LAB_ROOT} e recria o ambiente."
  say "${warn_msg}"
  read -r -p "Continuar? [s/N] " ans || true
  case "${ans}" in
    s|S|sim|SIM|y|Y) return 0 ;;
    *) die "Operação cancelada." ;;
  esac
}

obtain_setup_to() {
  local dest="$1"
  if [[ -n "${SETUP_SRC}" ]]; then
    [[ -f "${SETUP_SRC}" ]] || die "setup não encontrado: ${SETUP_SRC}"
    cp "${SETUP_SRC}" "${dest}"
    say "Usando setup: ${SETUP_SRC}"
    return
  fi
  local script_dir=""
  if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  fi
  if [[ -f "${PWD}/setup_inovatech.sh" ]]; then
    cp "${PWD}/setup_inovatech.sh" "${dest}"
    say "Usando ./setup_inovatech.sh"
    return
  fi
  if [[ -n "${script_dir}" && -f "${script_dir}/setup_inovatech.sh" ]]; then
    cp "${script_dir}/setup_inovatech.sh" "${dest}"
    say "Usando ${script_dir}/setup_inovatech.sh"
    return
  fi
  say "Baixando setup_inovatech.sh..."
  if command -v curl &>/dev/null; then
    curl -fsSL "${GITHUB_RAW}/setup_inovatech.sh" -o "${dest}"
  elif command -v wget &>/dev/null; then
    wget -q "${GITHUB_RAW}/setup_inovatech.sh" -O "${dest}"
  else
    die "curl/wget ausentes; passe --setup-src ou rode desde o clone do repo."
  fi
}

install_bins_from_setup_file() {
  local setup_file="$1"
  [[ -s "${setup_file}" ]] || die "Arquivo de setup vazio ou ausente."

  local td
  td="$(mktemp -d)"
  trap 'rm -rf "${td}"' RETURN

  awk '
    /^cat > \/tmp\/inovatech-submit << .SUBMIT_SCRIPT.$/ {skip=1; next}
    skip && /^SUBMIT_SCRIPT$/ {exit}
    skip {print}
  ' "${setup_file}" > "${td}/inovatech-submit"
  awk '
    /^cat > \/tmp\/inovatech-enviar-entrega << .ENVIAR_SCRIPT.$/ {skip=1; next}
    skip && /^ENVIAR_SCRIPT$/ {exit}
    skip {print}
  ' "${setup_file}" > "${td}/inovatech-enviar-entrega"
  awk '
    /^cat > \/tmp\/inovatech-preparar-entrega << .PREP_SCRIPT.$/ {skip=1; next}
    skip && /^PREP_SCRIPT$/ {exit}
    skip {print}
  ' "${setup_file}" > "${td}/inovatech-preparar-entrega"
  awk '
    /^cat > \/tmp\/inovatech-seal << .SEAL_SCRIPT.$/ {skip=1; next}
    skip && /^SEAL_SCRIPT$/ {exit}
    skip {print}
  ' "${setup_file}" > "${td}/inovatech-seal"
  awk '
    /^cat > \/tmp\/inovatech-verify << .VERIFY_SCRIPT.$/ {skip=1; next}
    skip && /^VERIFY_SCRIPT$/ {exit}
    skip {print}
  ' "${setup_file}" > "${td}/inovatech-verify"
  awk '
    /^cat > \/tmp\/inovatech-versions << .VERSIONS_SCRIPT.$/ {skip=1; next}
    skip && /^VERSIONS_SCRIPT$/ {exit}
    skip {print}
  ' "${setup_file}" > "${td}/inovatech-versions"

  local f
  for f in submit enviar-entrega preparar-entrega seal verify versions; do
    [[ -s "${td}/inovatech-${f}" ]] || die "Extração falhou: inovatech-${f}"
    chmod +x "${td}/inovatech-${f}"
  done

  if [[ "$(id -u)" -eq 0 ]]; then
    cp "${td}/inovatech-submit" /usr/local/bin/
    cp "${td}/inovatech-enviar-entrega" /usr/local/bin/
    cp "${td}/inovatech-preparar-entrega" /usr/local/bin/
    cp "${td}/inovatech-seal" /usr/local/bin/
    cp "${td}/inovatech-verify" /usr/local/bin/
    cp "${td}/inovatech-versions" /usr/local/bin/
    chmod +x /usr/local/bin/inovatech-*
  else
    sudo cp "${td}/inovatech-submit" /usr/local/bin/
    sudo cp "${td}/inovatech-enviar-entrega" /usr/local/bin/
    sudo cp "${td}/inovatech-preparar-entrega" /usr/local/bin/
    sudo cp "${td}/inovatech-seal" /usr/local/bin/
    sudo cp "${td}/inovatech-verify" /usr/local/bin/
    sudo cp "${td}/inovatech-versions" /usr/local/bin/
    sudo chmod +x /usr/local/bin/inovatech-*
  fi
  say "Comandos inovatech-* instalados em /usr/local/bin."
}

run_online_update() {
  ensure_sudo
  local old_hash
  old_hash="$(read_old_public_hash)"
  if [[ -n "${old_hash}" ]]; then
    say "Hash público anterior (se existia .seal): ${old_hash}"
  fi

  confirm_reset

  mkdir -p "${LAB_ROOT}"
  local setup_tmp
  setup_tmp="$(mktemp)"
  trap 'rm -f "${setup_tmp}"' EXIT
  obtain_setup_to "${setup_tmp}"
  bash -n "${setup_tmp}" || die "setup obtido falhou em bash -n."

  (
    cd "${LAB_ROOT}"
    export INOVATECH_LAB_RESET=1
    bash "${setup_tmp}"
  )

  if [[ "${NO_SEAL}" != "1" ]]; then
    say "Executando inovatech-seal..."
    ( cd "${LAB_ROOT}" && inovatech-seal --dir "${LAB_ROOT}" )
    # Selagem remove o binário seal; reinstalar todos para próxima manutenção.
    install_bins_from_setup_file "${setup_tmp}"
  fi

  say "Executando inovatech-verify..."
  ( cd "${LAB_ROOT}" && inovatech-verify --dir "${LAB_ROOT}" )

  say "Atualização online concluída."
}

resolve_offline_staging() {
  local bundle="$1"
  local stage
  if [[ -d "${bundle}" ]]; then
    echo "${bundle}"
    return
  fi
  if [[ -f "${bundle}" ]]; then
    stage="$(mktemp -d)"
    tar -xzf "${bundle}" -C "${stage}"
    # Pacote: um único diretório filho
    local children
    children=( "${stage}"/* )
    if [[ ${#children[@]} -eq 1 && -d "${children[0]}" ]]; then
      echo "${children[0]}"
      return
    fi
    die "Layout do tarball inválido: espere um diretório raiz único."
  fi
  die "Bundle offline não encontrado: ${bundle}"
}

run_offline_update() {
  [[ -n "${OFFLINE_BUNDLE}" ]] || die "Falta --offline-bundle."
  ensure_sudo

  local old_hash
  old_hash="$(read_old_public_hash)"
  if [[ -n "${old_hash}" ]]; then
    say "Hash público anterior: ${old_hash}"
  fi

  confirm_reset

  local stage_root setup_in_bundle
  stage_root="$(resolve_offline_staging "${OFFLINE_BUNDLE}")"

  setup_in_bundle=""
  if [[ -f "${stage_root}/setup_inovatech.sh" ]]; then
    setup_in_bundle="${stage_root}/setup_inovatech.sh"
  else
    die "Pacote offline sem setup_inovatech.sh em ${stage_root}"
  fi

  local src_tree="${stage_root}/inovatech"
  [[ -d "${src_tree}" ]] || die "Pacote offline sem inovatech/ em ${stage_root}"

  if [[ -f "${stage_root}/MANIFEST.txt" ]]; then
    say "MANIFEST do pacote:"
    cat "${stage_root}/MANIFEST.txt"
  fi

  rm -rf "${LAB_ROOT}"
  mkdir -p "${LAB_ROOT}"
  cp -a "${src_tree}/." "${LAB_ROOT}/"

  install_bins_from_setup_file "${setup_in_bundle}"

  if [[ "${NO_SEAL}" != "1" ]]; then
    say "Executando inovatech-seal..."
    ( cd "${LAB_ROOT}" && inovatech-seal --dir "${LAB_ROOT}" )
    install_bins_from_setup_file "${setup_in_bundle}"
  fi

  say "Executando inovatech-verify..."
  ( cd "${LAB_ROOT}" && inovatech-verify --dir "${LAB_ROOT}" )

  if [[ -f "${stage_root}/MANIFEST.txt" ]]; then
    local expected got
    expected="$(grep -E '^EXPECTED_VERIFY_HASH=' "${stage_root}/MANIFEST.txt" \
      | head -n1 | cut -d= -f2- | tr -d '\r' || true)"
    got="$(grep -Eo '[0-9a-f]{64}' "${LAB_ROOT}/.seal/hash_publico.txt" 2>/dev/null \
      | head -n1 || true)"
    if [[ -n "${expected}" && -n "${got}" && "${expected}" != "${got}" ]]; then
      die "Hash após selagem (${got}) difere do esperado no pacote (${expected})."
    fi
  fi

  say "Atualização offline concluída."
}

main() {
  say "LAB_ROOT=${LAB_ROOT}"
  if [[ -n "${OFFLINE_BUNDLE}" ]]; then
    run_offline_update
  else
    if ! have_sudo && [[ "$(id -u)" -ne 0 ]]; then
      say "Aviso: sudo pode solicitar senha em seguida."
    fi
    run_online_update
  fi
}

main "$@"
