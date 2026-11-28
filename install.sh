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
OPT_AGENT_HOST=0

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
  --no-services        Skip service setup (shell, keyd, snapper, Steam, Nvidia, voxtype, calendar timer if stowed, SSH server)
  --dev                Clone repos into $GITHUB_DIR (default ~/Development) for editing and link them
  --server             Headless install: shell/CLI/dev packages and configs only
  --agent-host         A --server install plus the nested-session packages, linger and a boot-time plans board
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
    --agent-host)
      OPT_AGENT_HOST=1
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

# Runs an optional step in a subshell with errexit on and turns a failure into a warning. "step || warn" would disable
# errexit inside the step, so a failed command in the middle would be ignored and the step would print a false success.
# errexit is switched off around the subshell, not inherited into a || list, for the same reason. The subshell drops the
# step's variable changes, which is safe: none of the optional steps sets a variable that a later step reads.
run_optional_step() {
  local step=$1 message=$2 status=0
  set +e
  (
    set -e
    "$step"
  )
  status=$?
  set -e
  if [[ $status -ne 0 ]]; then warn "$message"; fi
  return 0
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
  migrate_retire_tbkeys
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
  setup_git_hooks || true
  if [[ $OPT_SERVER -eq 0 ]]; then install_artcraft || warn "ArtCraft was not fully installed; fix the error above, then run: just artcraft-update"; fi
  if [[ $OPT_SERVER -eq 0 ]]; then install_voxcmd || warn "voxcmd was not built; fix the error above, then run: just voxcmd-build"; fi
  if [[ $OPT_SERVER -eq 0 ]]; then install_desertfox_host || warn "DesertFox hosts were not installed; fix the error above, then run: just desertfox-host"; fi
  install_nvim_config
  if [[ $OPT_SYSTEM_FILES -eq 1 ]]; then setup_root_symlinks; fi
  bootstrap_neovim
  if [[ $OPT_SYSTEM_FILES -eq 1 ]]; then install_system_files; fi
  if [[ $OPT_SYSTEM_FILES -eq 1 && $OPT_SERVER -eq 0 ]]; then install_desertfox_browser_module || warn "The DesertFox browser module was not installed; fix the error above, then rerun ./install.sh"; fi
  if [[ $OPT_SYSTEM_FILES -eq 1 ]]; then setup_pacman_tweaks; fi
  if [[ $OPT_SERVER -eq 1 && $OPT_SERVICES -eq 1 ]]; then
    set_default_shell
    run_optional_step setup_snapper "Snapper was not set up; fix the error above, then run: just snapper"
    setup_tailnet_ssh
    run_optional_step setup_syncthing "Syncthing was not set up; fix the error above, then run: just syncthing"
    if [[ $OPT_AGENT_HOST -eq 1 ]]; then setup_agent_host; fi
  elif [[ $OPT_SERVER -eq 0 && $OPT_SERVICES -eq 1 ]]; then
    run_optional_step install_greetd "greetd was not set up; fix the error above, then rerun ./install.sh"
    set_default_shell
    run_optional_step enable_keyd "keyd was not enabled; fix the error above, then rerun ./install.sh"
    run_optional_step enable_power_profiles "power-profiles-daemon was not enabled; fix the error above, then rerun ./install.sh"
    run_optional_step setup_snapper "Snapper was not set up; fix the error above, then run: just snapper"
    run_optional_step install_steam "Steam was not installed; fix the error above, then rerun ./install.sh"
    run_optional_step install_nvidia "The NVIDIA setup did not finish; fix the error above, then rerun ./install.sh"
    run_optional_step setup_voxtype "voxtype was not set up; fix the error above, then rerun ./install.sh"
    run_optional_step setup_calendar_timer "The calendar timer was not set up; fix the error above, then rerun ./install.sh"
    setup_tailnet_ssh
    run_optional_step setup_syncthing "Syncthing was not set up; fix the error above, then run: just syncthing"
  fi

  # Outside the services branch, so --minimal and --no-services installs drop the home leftovers too. The system ones
  # (xpi, policy entry) need system files on.
  if [[ $OPT_SERVER -eq 0 ]]; then
    retire_voxcmd_firefox_extension || warn "The old voxcmd Firefox extension was not fully removed; run: just retire-firefox-extension"
  fi

  print_manual_installs

  echo ""
  success "Done!"
  if [[ $OPT_SERVER -eq 0 ]]; then print_next_steps; fi
  echo ""
}

main "$@"
