#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$DOTFILES_DIR/lib/install/load.sh"
require_arch

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
  --no-services        Skip service setup (shell, keyd, Steam, Nvidia, voxtype, calendar timer if stowed, SSH server)
  --dev                Clone repos into $GITHUB_DIR (default ~/Development) for editing and link them
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
    --dev)
      # shellcheck disable=SC2034  # read by lib/install/repos.sh, which shellcheck cannot follow through load.sh's glob
      OPT_DEV=1
      ;;
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

# Checks for the Lua-config Hyprland runtime, then says how to start the session the installer set up.
print_next_steps() {
  if ! command -v start-hyprland &>/dev/null; then
    warn "start-hyprland not found: this config needs a Hyprland build with the Lua config API (the hyprland package)"
    return
  fi
  if systemctl is-enabled greetd &>/dev/null; then
    warn "Next: reboot to log in through greetd"
  else
    warn "Next: reboot, or log out and run start-hyprland from a TTY"
  fi
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
  migrate_unfold_systemd
  migrate_quickshell_lock_assets
  migrate_quickshell_state
  migrate_quickshell_input
  migrate_quickshell_weather
  do_stow "${core[@]}"
  seed_generated_defaults "${core[@]}"

  if command -v ya >/dev/null 2>&1 && [[ -f "$HOME/.config/yazi/package.toml" ]]; then
    info "Installing Yazi packages..."
    if ! ya pkg install; then
      warn "Failed to install Yazi packages; continuing"
    fi
    # ya pkg wrote pins the committed list leaves out (git's yazi-plugin-pins filter); git add only refreshes the index, so
    # the larger file does not read as modified and block the next pull.
    git -C "$DOTFILES_DIR" add -- home/yazi/.config/yazi/package.toml 2>/dev/null || true
  fi

  SELECTED_OPTIONAL=()
  if [[ $OPT_SERVER -eq 0 ]]; then prompt_optional; fi
  if [[ ${#SELECTED_OPTIONAL[@]} -gt 0 ]]; then
    info "Stowing optional packages..."
    do_stow "${SELECTED_OPTIONAL[@]}"
    seed_generated_defaults "${SELECTED_OPTIONAL[@]}"
  fi

  setup_git_identity
  if [[ $OPT_SERVER -eq 0 ]]; then install_voxcmd || warn "voxcmd was not built; fix the error above, then run: just voxcmd-build"; fi
  install_nvim_config
  if [[ $OPT_SYSTEM_FILES -eq 1 ]]; then setup_root_symlinks; fi
  bootstrap_neovim
  if [[ $OPT_SYSTEM_FILES -eq 1 ]]; then install_system_files; fi
  if [[ $OPT_SYSTEM_FILES -eq 1 ]]; then setup_pacman_tweaks; fi
  if [[ $OPT_SERVER -eq 1 && $OPT_SERVICES -eq 1 ]]; then
    set_default_shell
    setup_tailnet_ssh
  elif [[ $OPT_SERVER -eq 0 && $OPT_SERVICES -eq 1 ]]; then
    install_greetd
    set_default_shell
    enable_keyd
    enable_power_profiles
    install_steam
    install_nvidia
    setup_voxtype
    setup_calendar_timer
    register_firefox_host --quiet
    install_firefox_extension_policy --quiet || warn "The Firefox extension policy was not installed; run: just firefox-extension"
    setup_tailnet_ssh
  fi

  print_manual_installs

  echo ""
  success "Done!"
  if [[ $OPT_SERVER -eq 0 ]]; then print_next_steps; fi
  echo ""
}

main "$@"
