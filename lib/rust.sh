#!/usr/bin/env bash
# Installs Rust via rustup and cargo packages from cargo.ini.

bootstrap_rust() {
  info "Bootstrapping Rust (rustup)..."
  if command -v rustup &>/dev/null; then
    warn "rustup already present, skipping"
    return
  fi
  case "$DISTRO" in
  fedora) sudo dnf install -y rustup ;;
  arch) sudo pacman -S --needed --noconfirm rustup ;;
  esac
  rustup toolchain install stable
  rustup toolchain install nightly
  # shellcheck source=/dev/null
  source "$HOME/.cargo/env"
  success "Rust installed"
}

install_cargo_packages() {
  info "Installing cargo packages..."
  if ! command -v cargo &>/dev/null; then
    warn "cargo not in PATH, skipping"
    return
  fi
  mapfile -t pkgs < <(read_ini_section cargo.ini "${DISTRO^^}")
  [[ ${#pkgs[@]} -eq 0 ]] && {
    warn "no cargo packages for $DISTRO, skipping"
    return
  }
  cargo install --locked "${pkgs[@]}" && success "Cargo packages installed" || warn "Some cargo packages failed to install"
}
