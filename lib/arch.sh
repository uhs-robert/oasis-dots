#!/usr/bin/env bash
# Arch-specific setup: bootstraps paru and installs AUR packages.

# Builds and installs paru from source if not already present.
bootstrap_paru() {
  command -v paru &>/dev/null && return
  info "Installing paru (AUR helper)..."
  sudo pacman -S --needed --noconfirm base-devel git
  local tmp
  tmp=$(mktemp -d)
  git clone https://aur.archlinux.org/paru.git "$tmp/paru"
  (cd "$tmp/paru" && makepkg -si --noconfirm)
  rm -rf "$tmp"
  success "paru installed"
}

install_aur_packages() {
  [[ "$DISTRO" != arch ]] && return
  bootstrap_paru
  info "Installing AUR packages..."
  mapfile -t pkgs < <(read_pkgs arch-aur.ini)
  paru -S --needed --noconfirm "${pkgs[@]}"
  success "AUR packages installed"
}
