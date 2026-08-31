#!/usr/bin/env bash
# Detects the running distro and sets shared path variables.
# Sets $DISTRO (arch), $PKG_DIR, $GITHUB_DIR, $GITHUB_ORG at source time.

# shellcheck disable=SC2034  # consumed by other sourced lib/*.sh
GITHUB_DIR="$HOME/Development"
# shellcheck disable=SC2034  # consumed by other sourced lib/*.sh
GITHUB_ORG="uhs-robert"
# shellcheck disable=SC2034  # consumed by other sourced lib/*.sh
PKG_DIR="$DOTFILES_DIR/packages"

detect_distro() {
  if command -v pacman &>/dev/null; then
    echo arch
  else
    die "Unsupported distro, only Arch is supported."
  fi
}

DISTRO=$(detect_distro)
info "Detected: $DISTRO"
