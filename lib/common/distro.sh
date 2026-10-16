#!/usr/bin/env bash
# Detects the running distro and sets shared path variables.
# Sets $PKG_DIR, $GITHUB_DIR, $GITHUB_ORG, $REPOS_DIR, $REPOS_LINK at source time, silently.
# $DISTRO (arch) is set by require_arch, which install.sh and uninstall.sh call; sourcing must stay free of output and exits.

# Environment wins over the ignored install.local, which wins over the defaults.
_env_github_dir="${GITHUB_DIR:-}"
_env_github_org="${GITHUB_ORG:-}"
# shellcheck source=/dev/null
[[ -f "$DOTFILES_DIR/install.local" ]] && source "$DOTFILES_DIR/install.local"
# shellcheck disable=SC2034  # consumed by other sourced lib files
GITHUB_DIR="${_env_github_dir:-${GITHUB_DIR:-$HOME/Development}}"
# shellcheck disable=SC2034  # consumed by other sourced lib files
GITHUB_ORG="${_env_github_org:-${GITHUB_ORG:-uhs-robert}}"
unset _env_github_dir _env_github_org
# shellcheck disable=SC2034  # consumed by other sourced lib files
PKG_DIR="$DOTFILES_DIR/packages"
# shellcheck disable=SC2034  # consumed by other sourced lib files
REPOS_DIR="$DOTFILES_DIR/repos"
# shellcheck disable=SC2034  # stable path for configs that cannot find the dotfiles checkout
REPOS_LINK="$HOME/.local/share/dotfiles/repos"

detect_distro() {
  if command -v pacman &>/dev/null; then
    echo arch
  else
    die "Unsupported distro, only Arch is supported."
  fi
}

# Sets $DISTRO, announces it, and dies off Arch.
require_arch() {
  DISTRO=$(detect_distro)
  info "Detected: $DISTRO"
}
