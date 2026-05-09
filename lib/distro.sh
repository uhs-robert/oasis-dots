#!/usr/bin/env bash
# Detects the running distro and sets shared path variables.
# Sets $DISTRO (fedora|arch), $PKG_DIR, $GITHUB_DIR, $GITHUB_ORG at source time.

GITHUB_DIR="$HOME/Development"
GITHUB_ORG="uhs-robert"
PKG_DIR="$DOTFILES_DIR/packages"

detect_distro() {
  if command -v dnf &>/dev/null; then
    echo fedora
  elif command -v pacman &>/dev/null; then
    echo arch
  else
    die "Unsupported distro, only Fedora and Arch are supported."
  fi
}

DISTRO=$(detect_distro)
info "Detected: $DISTRO"
