#!/usr/bin/env bash
# Miscellaneous install steps: repos, dev tools, system files, services, and optional hardware.

clone_repos() {
  info "Cloning external repos → $GITHUB_DIR"
  mkdir -p "$GITHUB_DIR"
  while IFS= read -r repo; do
    local dest="$GITHUB_DIR/$repo"
    if [[ -d "$dest" ]]; then
      warn "$repo already exists, skipping"
    else
      git clone "https://github.com/$GITHUB_ORG/$repo" "$dest" &&
        success "Cloned $repo" ||
        warn "Failed to clone $repo (private repo? clone manually)"
    fi
  done < <(read_pkgs repos.ini)
}

install_devtool_nodejs() {
  if command -v fnm &>/dev/null; then warn "fnm already present, skipping"; return; fi
  info "Installing fnm (node version manager)..."
  if command -v cargo &>/dev/null; then
    cargo install fnm
  else
    curl -fsSL https://fnm.vercel.app/install | bash --no-use
  fi
  success "fnm installed, run: fnm install --lts"
}

install_devtool_pnpm() {
  if command -v pnpm &>/dev/null; then warn "pnpm already present, skipping"; return; fi
  info "Installing pnpm..."
  curl -fsSL https://get.pnpm.io/install.sh | sh -
  success "pnpm installed"
}

install_devtool_bun() {
  if command -v bun &>/dev/null; then warn "bun already present, skipping"; return; fi
  info "Installing bun..."
  curl -fsSL https://bun.sh/install | bash
  success "bun installed"
}

install_devtool_go() {
  if command -v go &>/dev/null; then warn "go already present, skipping"; return; fi
  info "Installing Go..."
  case "$DISTRO" in
  fedora) sudo dnf install -y golang ;;
  arch)   sudo pacman -S --needed --noconfirm go ;;
  esac
  success "Go installed"
}

install_devtool_deno() {
  if command -v deno &>/dev/null; then warn "deno already present, skipping"; return; fi
  info "Installing deno..."
  curl -fsSL https://deno.land/install.sh | sh
  success "deno installed"
}

# Presents an fzf picker of optional runtimes and dispatches to the right installer.
install_dev_tools() {
  echo ""
  info "Optional developer runtimes (Tab to select, Enter to confirm):"
  mapfile -t selected < <(
    read_ini_section devtools.ini TOOLS | fzf --multi --prompt="dev tools> " --no-info
  )
  [[ ${#selected[@]} -eq 0 ]] && return
  for tool in "${selected[@]}"; do
    case "$tool" in
    nodejs) install_devtool_nodejs ;;
    pnpm)   install_devtool_pnpm ;;
    bun)    install_devtool_bun ;;
    go)     install_devtool_go ;;
    deno)   install_devtool_deno ;;
    *)      warn "Unknown dev tool: $tool, skipping" ;;
    esac
  done
}

detect_primary_connector() {
  local connected=()
  for f in /sys/class/drm/*/status; do
    [[ "$(cat "$f" 2>/dev/null)" == "connected" ]] || continue
    local name
    name=$(basename "$(dirname "$f")")
    name="${name#card?-}"
    connected+=("$name")
  done
  case ${#connected[@]} in
  0) echo "eDP-1" ;;
  1) echo "${connected[0]}" ;;
  *) printf '%s\n' "${connected[@]}" | fzf --prompt="Primary display for greeter> " --no-info ;;
  esac
}

# Optionally installs greetd + tuigreet, deploys their configs, and enables the greetd service.
install_greetd() {
  confirm "Install greetd + tuigreet (display manager)?" || return 0

  info "Installing greetd and tuigreet..."
  case "$DISTRO" in
  fedora)
    sudo dnf install -y greetd tuigreet
    ;;
  arch)
    sudo pacman -S --needed --noconfirm greetd
    sudo pacman -S --needed --noconfirm greetd-tuigreet
    ;;
  esac

  cd "$DOTFILES_DIR"
  local connector
  connector=$(detect_primary_connector)
  info "Setting greeter primary display: $connector"
  local tmp
  tmp=$(mktemp --suffix=.toml)
  sed "s/connector = \"eDP-1\"/connector = \"$connector\"/" \
    system/etc/tuigreet/config.toml > "$tmp"
  sudo install -Dm644 system/etc/greetd/config.toml       /etc/greetd/config.toml
  sudo install -Dm644 "$tmp"                               /etc/tuigreet/config.toml
  sudo install -Dm755 system/usr/local/bin/tuigreet-oasis /usr/local/bin/tuigreet-oasis
  rm -f "$tmp"
  success "greetd/tuigreet config installed"

  sudo systemctl enable greetd
  success "greetd enabled (active on next boot)"
}

install_system_files() {
  info "Installing system config files..."
  cd "$DOTFILES_DIR"
  sudo install -Dm644 system/etc/vtrgb-oasis /etc/vtrgb-oasis
  sudo install -Dm644 system/etc/keyd/default.conf /etc/keyd/default.conf
  success "System config files installed"
}

set_default_shell() {
  local zsh_path
  zsh_path="$(which zsh)"
  if [[ "$SHELL" == "$zsh_path" ]]; then
    warn "zsh already default shell, skipping"
    return
  fi
  info "Setting default shell to zsh..."
  sudo usermod -s "$zsh_path" "$USER"
  success "Default shell set to zsh (takes effect on next login)"
}

enable_keyd() {
  if ! command -v keyd &>/dev/null; then
    warn "keyd not installed, skipping"
    return
  fi
  if systemctl is-enabled keyd &>/dev/null; then
    warn "keyd already enabled, skipping"
    return
  fi
  info "Enabling keyd..."
  sudo systemctl enable --now keyd
  success "keyd enabled"
}

# Builds and installs the xone Xbox controller kernel module from source.
install_xone() {
  info "Installing xone..."
  case "$DISTRO" in
  fedora) sudo dnf install -y dkms kernel-devel cabextract ;;
  arch) sudo pacman -S --needed --noconfirm dkms linux-headers cabextract ;;
  esac
  local tmp
  tmp=$(mktemp -d)
  git clone --recurse-submodules --branch v0.3 https://github.com/medusalix/xone "$tmp/xone"
  sudo bash "$tmp/xone/install.sh" --release
  rm -rf "$tmp"
  success "xone installed"
}

# Prompts for native vs Flatpak Steam; optionally installs xone afterwards.
install_steam() {
  confirm "Install Steam?" || return 0

  printf '\e[35m[?] \e[0mnative or flatpak? [native/flatpak] '
  read -r method

  case "$method" in
  flatpak)
    if ! command -v flatpak &>/dev/null; then
      case "$DISTRO" in
      fedora) sudo dnf install -y flatpak ;;
      arch) sudo pacman -S --needed --noconfirm flatpak ;;
      esac
    fi
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    if [[ "$DISTRO" != arch ]]; then
      mapfile -t gaming_apps < <(read_flatpak_section GAMING)
      install_flatpak_section "gaming" "${gaming_apps[@]}"
    fi
    flatpak install -y flathub com.valvesoftware.Steam
    ;;
  *)
    info "Installing Steam (native)..."
    case "$DISTRO" in
    fedora)
      sudo dnf install -y \
        "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
      sudo dnf install -y steam
      ;;
    arch)
      if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
        info "Enabling multilib repo..."
        sudo sed -i 's/^#\(\[multilib\]\)/\1/; /^\[multilib\]/{n;s/^#//}' /etc/pacman.conf
      fi
      sudo pacman -Syu --needed --noconfirm steam
      ;;
    esac
    ;;
  esac
  success "Steam installed"

  confirm "Install xone (Xbox controller driver)?" && install_xone || true
}

install_nvidia() {
  confirm "Install Nvidia drivers?" || return 0
  info "Installing Nvidia drivers..."
  case "$DISTRO" in
  fedora)
    sudo dnf install -y \
      "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
      "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
    sudo dnf install -y \
      akmod-nvidia \
      xorg-x11-drv-nvidia-cuda \
      libva-nvidia-driver \
      nvidia-settings
    ;;
  arch)
    sudo pacman -S --needed --noconfirm nvidia-utils libva-nvidia-driver nvidia-settings
    if confirm "Use nvidia-dkms instead of nvidia (for zen/lts/custom kernels)?"; then
      sudo pacman -S --needed --noconfirm nvidia-dkms linux-headers
    else
      sudo pacman -S --needed --noconfirm nvidia
    fi
    ;;
  esac
  success "Nvidia drivers installed (reboot required)"
}

setup_voxtype() {
  if ! command -v voxtype &>/dev/null; then
    case "$DISTRO" in
    arch) warn "voxtype should have been installed via AUR, check paru output above" ;;
    fedora) warn "voxtype not in Fedora repos, download the RPM from https://voxtype.io and re-run" ;;
    esac
    return
  fi
  info "Configuring voxtype..."
  if ! groups | grep -q '\binput\b'; then
    sudo usermod -aG input "$USER"
    warn "Added $USER to input group, takes effect on next login"
  fi
  voxtype setup model
  if systemctl --user show-environment &>/dev/null; then
    systemctl --user is-enabled voxtype &>/dev/null || systemctl --user enable --now voxtype
  else
    warn "User systemd not available, enable voxtype after login: systemctl --user enable --now voxtype"
  fi
  success "voxtype configured"
}
