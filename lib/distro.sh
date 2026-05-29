#!/usr/bin/env bash
# Detects the running distro and sets shared path variables.
# Sets $DISTRO (arch), $PKG_DIR, $GITHUB_DIR, $GITHUB_ORG at source time.

GITHUB_DIR="$HOME/Development"
GITHUB_ORG="uhs-robert"
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
