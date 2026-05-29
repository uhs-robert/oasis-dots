#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$DOTFILES_DIR/lib/output.sh"
source "$DOTFILES_DIR/lib/distro.sh"
source "$DOTFILES_DIR/lib/packages.sh"

OPT_SYSTEM_FILES=1
OPT_SERVICES=1
OPT_YES=0

usage() {
  cat <<EOF
Usage: uninstall.sh [OPTIONS]

Removes the Oasis dotfiles installation. Unstows all packages (removes symlinks
from ~), optionally removes installed system files, disables services, and
reverts the default shell. Does not remove system packages or Cargo/Rust
as those should be removed manually.

Options:
  --no-system-files    Skip removal of system files (/etc/greetd, etc.)
  --no-services        Skip disabling services (greetd, keyd, voxtype)
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
    --no-system-files) OPT_SYSTEM_FILES=0 ;;
    --no-services) OPT_SERVICES=0 ;;
    -y | --yes) OPT_YES=1 ;;
    *) die "Unknown flag: $1" ;;
    esac
    shift
  done
}

# Runs stow -D on every package in stow.ini (CORE + OPTIONAL), removing their symlinks from ~.
unstow_packages() {
  info "Unstowing packages..."
  cd "$DOTFILES_DIR"
  mapfile -t all_pkgs < <(
    read_ini_section stow.ini CORE
    read_ini_section stow.ini OPTIONAL
  )
  for pkg in "${all_pkgs[@]}"; do
    if [[ ! -d "home/$pkg" ]]; then
      continue
    fi
    if stow -D "$pkg" 2>/dev/null; then
      success "Unstowed $pkg"
    else
      warn "Could not unstow $pkg, may not have been stowed"
    fi
  done
}

# Prompts to remove system files installed by install_system_files/install_greetd.
remove_system_files() {
  [[ $OPT_SYSTEM_FILES -eq 0 ]] && return
  confirm "Remove installed system files (/etc/greetd, /etc/tuigreet, /etc/vtrgb-oasis, /usr/local/bin/tuigreet-oasis)?" || return

  local files=(
    /etc/greetd/config.toml
    /etc/tuigreet/config.toml
    /usr/local/bin/tuigreet-oasis
    /etc/vtrgb-oasis
  )
  for f in "${files[@]}"; do
    if [[ -f "$f" ]]; then
      sudo rm -f "$f" && success "Removed $f"
    else
      warn "$f not found, skipping"
    fi
  done
}

# Prompts to disable greetd, keyd, and voxtype if they are currently enabled.
disable_services() {
  [[ $OPT_SERVICES -eq 0 ]] && return

  if systemctl is-enabled greetd &>/dev/null; then
    confirm "Disable greetd?" && sudo systemctl disable greetd && success "greetd disabled"
  fi

  if systemctl is-enabled keyd &>/dev/null; then
    confirm "Disable keyd?" && sudo systemctl disable --now keyd && success "keyd disabled"
  fi

  if systemctl --user is-enabled voxtype &>/dev/null 2>&1; then
    confirm "Disable voxtype?" && systemctl --user disable --now voxtype && success "voxtype disabled"
  fi
}

# Reverts the default shell to bash if it was changed to zsh by the installer.
revert_shell() {
  local zsh_path bash_path
  zsh_path="$(which zsh 2>/dev/null || true)"
  bash_path="$(which bash)"

  if [[ -n "$zsh_path" && "$SHELL" == "$zsh_path" ]]; then
    confirm "Revert default shell from zsh to bash?" || return
    sudo usermod -s "$bash_path" "$USER"
    success "Default shell reverted to bash (takes effect on next login)"
  fi
}

# Prints instructions for components the script cannot safely remove automatically.
print_manual_steps() {
  cat <<'EOF'

 !  The following were NOT removed, uninstall manually if desired:

    System packages
      Arch : sudo pacman -Rs <pkg>
      List installed from this repo: see packages/arch.ini

    Cargo packages
      cargo uninstall <pkg>
      List installed: cat ~/.cargo/.crates.toml

    Rust / rustup
      rustup self uninstall
      Docs: https://rust-lang.github.io/rustup/installation/index.html

    Oh My Zsh
      $ZSH/tools/uninstall.sh
      Docs: https://github.com/ohmyzsh/ohmyzsh#uninstalling-oh-my-zsh

    tmuxifier
      rm -rf ~/.tmuxifier

    Cloned repos (~/Development)
      rm -rf ~/Development
      Review contents first, may include work you want to keep.

EOF
}

main() {
  parse_args "$@"

  echo ""
  info "Oasis dotfiles uninstall: $DISTRO"
  echo ""

  require_cmd sudo stow

  unstow_packages
  remove_system_files
  disable_services
  revert_shell
  print_manual_steps

  success "Done!"
}

main "$@"
