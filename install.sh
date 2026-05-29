#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$DOTFILES_DIR/lib/output.sh"
source "$DOTFILES_DIR/lib/distro.sh"
source "$DOTFILES_DIR/lib/packages.sh"
source "$DOTFILES_DIR/lib/arch.sh"
source "$DOTFILES_DIR/lib/rust.sh"
source "$DOTFILES_DIR/lib/stow.sh"
source "$DOTFILES_DIR/lib/services.sh"
source "$DOTFILES_DIR/lib/fonts.sh"

OPT_AUR=1
OPT_CARGO=1
OPT_SYSTEM_FILES=1
OPT_SERVICES=1
OPT_YES=0

usage() {
  cat <<EOF
Usage: install.sh [OPTIONS]

Sets up Oasis dotfiles on a fresh Arch system. Installs system packages,
optional runtimes, and Cargo/AUR packages, then symlinks dotfiles
into ~/ via GNU Stow. Prompts for optional components (greetd, Steam,
Nvidia, dev runtimes) throughout.

Options:
  -m, --minimal        Skip AUR, Rust, system files, and services
  --no-aur             Skip AUR packages
  --no-cargo           Skip Rust/rustup install
  --no-system-files    Skip system file installation (/etc/greetd, etc.)
  --no-services        Skip service setup (shell, keyd, Steam, Nvidia, voxtype)
  -y, --yes            Auto-confirm all prompts
  -h, --help           Show this help message
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    -m | --minimal)
      OPT_AUR=0
      OPT_CARGO=0
      OPT_SYSTEM_FILES=0
      OPT_SERVICES=0
      ;;
    --no-aur) OPT_AUR=0 ;;
    --no-cargo) OPT_CARGO=0 ;;
    --no-system-files) OPT_SYSTEM_FILES=0 ;;
    --no-services) OPT_SERVICES=0 ;;
    -y | --yes) OPT_YES=1 ;;
    *) die "Unknown flag: $1" ;;
    esac
    shift
  done
}

main() {
  parse_args "$@"

  echo ""
  info "Oasis dotfiles install: $DISTRO"
  echo ""

  require_cmd sudo
  ensure_cmd git awk grep sed

  install_packages
  [[ $OPT_AUR -eq 1 ]] && install_aur_packages
  install_luarocks_packages
  install_pipx_packages
  [[ $OPT_CARGO -eq 1 ]] && bootstrap_rust
  install_dev_tools
  clone_repos
  install_fonts
  bootstrap_omz
  bootstrap_tmuxifier

  info "Stowing core packages..."
  mapfile -t core < <(read_ini_section stow.ini CORE)
  do_stow "${core[@]}"

  SELECTED_OPTIONAL=()
  prompt_optional
  if [[ ${#SELECTED_OPTIONAL[@]} -gt 0 ]]; then
    info "Stowing optional packages..."
    do_stow "${SELECTED_OPTIONAL[@]}"
  fi

  template_user_configs
  setup_root_symlinks
  bootstrap_neovim
  install_greetd
  [[ $OPT_SYSTEM_FILES -eq 1 ]] && install_system_files
  if [[ $OPT_SERVICES -eq 1 ]]; then
    set_default_shell
    enable_keyd
    install_steam
    install_nvidia
    setup_voxtype
  fi

  print_manual_installs

  echo ""
  success "Done!"
  warn "Start Hyprland and run: hyprctl reload"
  echo ""
}

main "$@"
