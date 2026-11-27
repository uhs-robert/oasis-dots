#!/usr/bin/env bash
# System-level setup: files rsynced into /, the default shell, keyd, power-profiles-daemon and root's symlinks.

# Prints the first profile copy of bigicons.uc.js (under either root) and returns 0, or returns 1 when no profile has one.
# -e follows symlinks, so a chrome folder linked into a private repo counts. The profile copy is only the source the owner edits:
# mozilla.cfg runs the root-owned copy in chrome.d that install_system_files makes from it.
firefox_bigicons_source() {
  local script
  # Both roots Firefox uses: ~/.config/mozilla/firefox (XDG, newer builds) and ~/.mozilla/firefox.
  for script in "$HOME"/.config/mozilla/firefox/*/chrome/bigicons.uc.js "$HOME"/.mozilla/firefox/*/chrome/bigicons.uc.js; do
    if [[ -e $script ]]; then
      printf '%s\n' "$script"
      return 0
    fi
  done
  return 1
}

install_system_files() {
  info "Installing system config files..."
  cd "$DOTFILES_DIR" || return 1
  sudo install -Dm644 system/etc/vtrgb-oasis /etc/vtrgb-oasis
  sudo install -Dm644 system/etc/keyd/default.conf /etc/keyd/default.conf
  # ydotool (Cursor submap drag and drop) writes /dev/uinput; the rule gives the seat user that device only, not the input group.
  sudo install -Dm644 system/etc/udev/rules.d/70-dotfiles-uinput.rules /etc/udev/rules.d/70-dotfiles-uinput.rules
  # A copied rule reaches the existing /dev/uinput node only once udev reloads its rules and replays the node's add event.
  sudo udevadm control --reload
  sudo udevadm trigger --name-match=uinput
  # A lower CPUWeight on the user manager lets the login session (Hyprland, Firefox) win contended CPU; a running
  # user@.service takes the new weight on daemon-reload.
  sudo install -Dm644 system/etc/systemd/system/user@.service.d/50-cpuweight.conf /etc/systemd/system/user@.service.d/50-cpuweight.conf
  sudo systemctl daemon-reload
  sudo install -Dm644 system/etc/pacman.d/hooks/voxtype-gpu-setup.hook /etc/pacman.d/hooks/voxtype-gpu-setup.hook
  sudo install -Dm755 system/usr/local/bin/voxtype-gpu-setup /usr/local/bin/voxtype-gpu-setup
  # Firefox autoconfig: the package owns neither path (pacman -Qo), so upgrades leave them alone and no pacman hook is needed.
  # It is a root-level chrome-code hook, so it goes in only for a user who has the script it loads, and the script is a root-owned
  # copy in chrome.d beside mozilla.cfg: the profile is user-writable, so loading from it would turn any user file write into chrome code.
  # chrome.d is root, 0755 and made here whenever the autoconfig goes in; the gate has no "module wanted" leg yet (the DesertFox
  # browser module adds it). The script goes in first, then mozilla.cfg: autoconfig.js names it, and Firefox refuses to start
  # when that file is missing.
  local bigicons_source
  if [[ -d /usr/lib/firefox ]] && bigicons_source=$(firefox_bigicons_source); then
    sudo install -d -o root -g root -m755 /usr/lib/firefox/chrome.d
    sudo install -Dm644 "$bigicons_source" /usr/lib/firefox/chrome.d/bigicons.uc.js
    sudo install -Dm644 system/usr/lib/firefox/mozilla.cfg /usr/lib/firefox/mozilla.cfg
    sudo install -Dm644 system/usr/lib/firefox/defaults/pref/autoconfig.js /usr/lib/firefox/defaults/pref/autoconfig.js
  else
    info "No Firefox profile has chrome/bigicons.uc.js, skipping the Firefox autoconfig"
    # A copy from an earlier run would keep running after its profile source went away. Only the script goes: mozilla.cfg loads
    # whatever chrome.d holds without an error when it is empty, and autoconfig.js plus mozilla.cfg stay as a pair, the way
    # uninstall.sh keeps the cfg.
    if [[ -f /usr/lib/firefox/chrome.d/bigicons.uc.js ]]; then
      sudo rm -f /usr/lib/firefox/chrome.d/bigicons.uc.js && info "Removed the stale /usr/lib/firefox/chrome.d/bigicons.uc.js"
    fi
  fi
  # The copy that older installs put beside mozilla.cfg is no longer loaded, so it only misleads.
  if [[ -f /usr/lib/firefox/bigicons.uc.js ]]; then
    sudo rm -f /usr/lib/firefox/bigicons.uc.js && info "Removed the old /usr/lib/firefox/bigicons.uc.js"
  fi
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
