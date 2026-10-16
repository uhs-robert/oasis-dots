#!/usr/bin/env bash
# Optional hardware support: Nvidia drivers, the xone controller driver and Steam.

install_nvidia() {
  confirm "Install Nvidia drivers?" || return 0
  info "Installing Nvidia drivers..."
  local kernel_section=MODULE
  confirm "Use nvidia-dkms instead of nvidia (for zen/lts/custom kernels)?" && kernel_section=DKMS
  mapfile -t pkgs < <(read_ini_section nvidia.ini USERSPACE && read_ini_section nvidia.ini "$kernel_section")
  sudo pacman -S --needed --noconfirm "${pkgs[@]}"
  success "Nvidia drivers installed (reboot required)"
}

detect_gpu_vendor() {
  if lspci 2>/dev/null | grep -qiE 'amd|radeon'; then
    echo "amd"
  elif lspci 2>/dev/null | grep -qi 'nvidia'; then
    echo "nvidia"
  elif lspci 2>/dev/null | grep -qi 'intel.*vga\|vga.*intel'; then
    echo "intel"
  fi
}

# Builds and installs the xone Xbox controller kernel module from source.
install_xone() {
  info "Installing xone..."
  sudo pacman -S --needed --noconfirm dkms linux-headers cabextract
  local tmp
  tmp=$(mktemp -d)
  git clone --recurse-submodules --branch v0.3 https://github.com/medusalix/xone "$tmp/xone"
  sudo bash "$tmp/xone/install.sh" --release
  rm -rf "$tmp"
  success "xone installed"
}

# Prompts for native vs Flatpak Steam; optionally installs xone afterwards.
install_steam() {
  confirm "Install Steam? Native Steam enables [multilib] and runs a full pacman -Syu" || return 0

  if [[ $OPT_YES -eq 1 ]]; then
    method=native
    info "Steam install method: native (--yes)"
  else
    printf '\e[35m[?] \e[0mnative or flatpak? [native/flatpak] '
    read -r method
  fi

  case "$method" in
  flatpak)
    if ! command -v flatpak &>/dev/null; then
      sudo pacman -S --needed --noconfirm flatpak
    fi
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    flatpak install -y flathub com.valvesoftware.Steam
    ;;
  *)
    info "Installing Steam (native)..."
    if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
      info "Enabling multilib repo..."
      sudo sed -i 's/^#\(\[multilib\]\)/\1/; /^\[multilib\]/{n;s/^#//}' /etc/pacman.conf
    fi
    sudo pacman -Syu --needed --noconfirm steam
    ;;
  esac
  success "Steam installed"

  confirm "Install xone (Xbox controller driver)?" && install_xone || true
}
