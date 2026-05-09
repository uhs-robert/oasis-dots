#!/usr/bin/env bash
# Installs Flatpak apps from flathub. Skipped on Arch (uses native packages instead).

read_flatpak_section() {
  read_ini_section flatpak.ini "$1"
}

install_flatpak_section() {
  local label="$1"; shift
  local apps=("$@")
  [[ ${#apps[@]} -eq 0 ]] && return
  info "Installing $label Flatpak packages..."
  for app in "${apps[@]}"; do
    flatpak install -y flathub "$app" && success "Installed $app" || warn "Failed to install $app"
  done
}

install_flatpak_packages() {
  [[ "$DISTRO" == arch ]] && return
  info "Installing Flatpak packages..."
  if ! command -v flatpak &>/dev/null; then
    sudo dnf install -y flatpak
  fi
  flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

  mapfile -t core_apps     < <(read_flatpak_section CORE)
  mapfile -t games_apps    < <(read_flatpak_section GAMES)
  mapfile -t security_apps < <(read_flatpak_section SECURITY)

  install_flatpak_section "core" "${core_apps[@]}"

  confirm "Install games (SRB2)?" && install_flatpak_section "games" "${games_apps[@]}"
  confirm "Install security Flatpak packages (Bitwarden)?" && install_flatpak_section "security" "${security_apps[@]}"
}
