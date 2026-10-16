#!/usr/bin/env bash
# System-level setup: files rsynced into /, the default shell, keyd, power-profiles-daemon and root's symlinks.

install_system_files() {
  info "Installing system config files..."
  cd "$DOTFILES_DIR" || return 1
  sudo install -Dm644 system/etc/vtrgb-oasis /etc/vtrgb-oasis
  sudo install -Dm644 system/etc/keyd/default.conf /etc/keyd/default.conf
  sudo install -Dm644 system/etc/pacman.d/hooks/voxtype-gpu-setup.hook /etc/pacman.d/hooks/voxtype-gpu-setup.hook
  sudo install -Dm755 system/usr/local/bin/voxtype-gpu-setup /usr/local/bin/voxtype-gpu-setup
  sudo install -Dm644 system/etc/pacman.d/hooks/betterbird-autoconfig.hook /etc/pacman.d/hooks/betterbird-autoconfig.hook
  sudo install -Dm755 system/usr/local/bin/betterbird-autoconfig-setup /usr/local/bin/betterbird-autoconfig-setup
  sudo install -Dm644 system/opt/betterbird/defaults/pref/autoconfig.js /usr/local/share/betterbird-autoconfig/autoconfig.js
  sudo install -Dm644 system/opt/betterbird/betterbird.cfg /usr/local/share/betterbird-autoconfig/betterbird.cfg
  success "System config files installed"

  if [[ -d /opt/betterbird ]]; then
    info "Applying Betterbird tbkeys autoconfig..."
    sudo /usr/local/bin/betterbird-autoconfig-setup
    success "Betterbird tbkeys autoconfig applied"
  fi
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

enable_power_profiles() {
  if ! command -v powerprofilesctl &>/dev/null; then
    warn "power-profiles-daemon not installed, skipping"
    return
  fi
  if systemctl is-enabled power-profiles-daemon &>/dev/null; then
    warn "power-profiles-daemon already enabled, skipping"
    return
  fi
  info "Enabling power-profiles-daemon..."
  sudo systemctl enable --now power-profiles-daemon
  success "power-profiles-daemon enabled"
}

setup_root_symlinks() {
  confirm "Link root's shell and Yazi config to your user config (uses sudo)?" || return 0
  info "Setting up root symlinks..."
  sudo mkdir -p /root/.config/yazi

  sudo ln -sfn "$HOME/.zshrc" /root/.zshrc
  sudo ln -sfn "$HOME/.zsh_plugins.txt" /root/.zsh_plugins.txt
  sudo ln -sfn "$HOME/.config/nvim" /root/.config/nvim

  for item in flavors plugins yazi.toml; do
    sudo ln -sfn "$HOME/.config/yazi/$item" "/root/.config/yazi/$item"
  done

  # Launcher that keeps root's Yazi keymap in sync with the user's, plus a shim
  # on sudo's secure_path so plain "sudo yazi" syncs too.
  sudo install -Dm755 "$DOTFILES_DIR/system/usr/local/bin/yazi-root" /usr/local/bin/yazi-root
  sudo install -Dm755 "$DOTFILES_DIR/system/usr/local/sbin/yazi" /usr/local/sbin/yazi

  if [[ -f "$HOME/.config/yazi/keymap.toml" ]]; then
    /usr/local/bin/yazi-root --sync-only
    success "Generated root Yazi keymap (rerun 'just sync-root-yazi' or launch 'yazi-root' to refresh)"
  else
    warn "Yazi keymap not found, skipping root keymap generation"
  fi

  sudo tee /root/.config/yazi/theme.toml >/dev/null <<'EOF'
[flavor]
dark = "oasis-sol-dark"
EOF

  success "Root symlinks set"
}
