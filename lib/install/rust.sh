#!/usr/bin/env bash
# Installs Rust via rustup.

bootstrap_rust() {
  info "Bootstrapping Rust (rustup)..."
  if command -v rustup &>/dev/null; then
    warn "rustup already present, skipping"
    return
  fi
  sudo pacman -S --needed --noconfirm rustup
  rustup toolchain install stable
  rustup toolchain install nightly
  # shellcheck source=/dev/null
  source "$HOME/.cargo/env"
  success "Rust installed"
}
