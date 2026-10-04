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
source "$DOTFILES_DIR/lib/greeter.sh"
source "$DOTFILES_DIR/lib/repos.sh"
source "$DOTFILES_DIR/lib/fonts.sh"

OPT_AUR=1
OPT_CARGO=1
OPT_SYSTEM_FILES=1
OPT_SERVICES=1
OPT_YES=0
OPT_DEV=0
OPT_SERVER=0

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
  --no-system-files    Skip system files (/etc, /usr/local) and root links
  --no-services        Skip service setup (shell, keyd, Steam, Nvidia, voxtype)
  --dev                Clone repos into $GITHUB_DIR for editing and link them
  --server             Headless install: shell/CLI/dev packages and configs only
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
    --dev) OPT_DEV=1 ;;
    --server)
      OPT_SERVER=1
      OPT_CARGO=0
      OPT_SYSTEM_FILES=0
      ;;
    -y | --yes) OPT_YES=1 ;;
    *) die "Unknown flag: $1" ;;
    esac
    shift
  done
}

main() {
  parse_args "$@"
  trap print_failed_packages EXIT

  echo ""
  info "Oasis dotfiles install: $DISTRO"
  echo ""

  require_cmd sudo
  ensure_cmd git awk grep sed

  install_packages
  if [[ $OPT_AUR -eq 1 ]]; then install_aur_packages; fi
  install_luarocks_packages
  install_pipx_packages
  if [[ $OPT_CARGO -eq 1 ]]; then bootstrap_rust; fi
  if [[ $OPT_SERVER -eq 0 ]]; then install_dev_tools; fi
  clone_repos
  if [[ $OPT_SERVER -eq 0 ]]; then install_fonts; fi
  bootstrap_tmuxifier

  local stow_section=CORE
  if [[ $OPT_SERVER -eq 1 ]]; then stow_section=SERVER; fi
  info "Stowing ${stow_section,,} packages..."
  mapfile -t core < <(read_ini_section stow.ini "$stow_section")
  do_stow "${core[@]}"
  seed_generated_defaults "${core[@]}"

  if command -v ya >/dev/null 2>&1 && [[ -f "$HOME/.config/yazi/package.toml" ]]; then
    info "Installing Yazi packages..."
    if ! ya pkg install; then
      warn "Failed to install Yazi packages; continuing"
    fi
  fi

  SELECTED_OPTIONAL=()
  if [[ $OPT_SERVER -eq 0 ]]; then prompt_optional; fi
  if [[ ${#SELECTED_OPTIONAL[@]} -gt 0 ]]; then
    info "Stowing optional packages..."
    do_stow "${SELECTED_OPTIONAL[@]}"
    seed_generated_defaults "${SELECTED_OPTIONAL[@]}"
  fi

  setup_git_identity
  install_nvim_config
  if [[ $OPT_SYSTEM_FILES -eq 1 ]]; then setup_root_symlinks; fi
  bootstrap_neovim
  if [[ $OPT_SYSTEM_FILES -eq 1 ]]; then install_system_files; fi
  if [[ $OPT_SERVER -eq 1 && $OPT_SERVICES -eq 1 ]]; then
    set_default_shell
  elif [[ $OPT_SERVER -eq 0 && $OPT_SERVICES -eq 1 ]]; then
    install_greetd
    set_default_shell
    enable_keyd
    enable_power_profiles
    install_steam
    install_nvidia
    setup_voxtype
  fi

  print_manual_installs

  echo ""
  success "Done!"
  if [[ $OPT_SERVER -eq 0 ]]; then print_next_steps; fi
  echo ""
}

main "$@"
