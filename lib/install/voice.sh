#!/usr/bin/env bash
# Voice input: voxtype setup, plus the cleanup of the retired voxcmd Firefox extension.

# Builds the voxcmd crate under ~/.local/share/voxcmd-rs and links ~/.local/bin/voxcmd (and voxcmd-rs) to it, as `just
# voxcmd-build` does. install.sh calls it after stowing: a build, not stow, makes the voxcmd link now, so a failed build
# leaves whatever link was there (a stow link from before the swap) in place.
install_voxcmd() {
  # The binary bakes in the checkout it was built from (share dir, autostop path), which a linked worktree may outlive.
  # Same rule as `just voxcmd-build`; a non-git DOTFILES_DIR has no worktree to refuse.
  if [[ $(git -C "$DOTFILES_DIR" rev-parse --git-dir 2>/dev/null) != "$(git -C "$DOTFILES_DIR" rev-parse --git-common-dir 2>/dev/null)" ]]; then
    warn "$DOTFILES_DIR is a linked worktree, so voxcmd was not built; run in the main checkout: just voxcmd-build"
    return 0
  fi
  if ! command -v cargo &>/dev/null; then
    warn "cargo not found, so voxcmd was not built; install Rust, then run: just voxcmd-build"
    return 0
  fi
  local root="${XDG_DATA_HOME:-$HOME/.local/share}/voxcmd-rs" hash
  hash=$(git -C "$DOTFILES_DIR" describe --always --dirty --abbrev=9 --exclude='*' 2>/dev/null || echo unknown)
  info "Building voxcmd..."
  VOXCMD_GIT_HASH=$hash cargo install --path "$DOTFILES_DIR/home/voxcmd" --locked --root "$root" || return 1
  mkdir -p "$HOME/.local/bin"
  ln -sf "$root/bin/voxcmd" "$HOME/.local/bin/voxcmd-rs"
  ln -sf "$root/bin/voxcmd" "$HOME/.local/bin/voxcmd"
  success "voxcmd installed: ~/.local/bin/voxcmd"
}

setup_voxtype() {
  if ! command -v voxtype &>/dev/null; then
    warn "voxtype should have been installed via AUR, check paru output above"
    return
  fi
  info "Configuring voxtype..."
  if ! groups | grep -q '\binput\b'; then
    sudo usermod -aG input "$USER"
    warn "Added $USER to input group, takes effect on next login"
  fi

  local gpu_conf="$HOME/.config/systemd/user/voxtype.service.d/gpu.conf"
  [[ -L "$gpu_conf" && ! -e "$gpu_conf" ]] && rm -f "$gpu_conf"
  if [[ -L "$gpu_conf" ]]; then
    warn "gpu.conf is a dotfiles symlink, skipping GPU detection"
  elif command -v lspci &>/dev/null; then
    local vendor
    vendor=$(detect_gpu_vendor)
    if [[ -n "$vendor" ]]; then
      mkdir -p "$(dirname "$gpu_conf")"
      printf '[Service]\nEnvironment="VOXTYPE_GPU_DEVICE=0"\nEnvironment="VOXTYPE_VULKAN_DEVICE=%s"\n' "$vendor" >"$gpu_conf"
      success "voxtype GPU drop-in written: $vendor"
    else
      warn "Could not detect GPU vendor, skipping gpu.conf"
    fi
  else
    warn "lspci not available, skipping gpu.conf"
  fi

  local model
  model=$(sed -n 's/^model = "\(.*\)"/\1/p' "$HOME/.config/voxtype/config.toml" 2>/dev/null | head -n1)
  if confirm "Download the voxtype whisper model (${model:-default}, can be over 1 GB)?"; then
    voxtype setup model
  else
    warn "Skipped model download, run later: voxtype setup model"
  fi
  # The Cortana listener confirms triggers with base.en (VOXCMD_WAKE_CONFIRM_MODEL), a 141 MB download that the
  # interactive picker above does not offer. Without --activate it changes no daemon setting.
  voxtype setup --download --model base.en --no-post-install || warn "base.en download failed, the Cortana listener falls back to the daemon's model; run later: voxtype setup --download --model base.en"
  # Small, and config.toml enables VAD with it.
  voxtype setup vad >/dev/null || warn "VAD model download failed, run later: voxtype setup vad"
  # voxtype writes its own unit and enables and starts it; the stowed voxtype.service.d/prompt.conf adjusts it.
  if systemctl --user show-environment &>/dev/null; then
    voxtype setup systemd || warn "voxtype setup systemd failed, run it after login"
  else
    warn "User systemd not available, run after login: voxtype setup systemd"
  fi
  # `voxtype setup systemd` exits 0 even when its systemctl calls fail.
  if systemctl --user show-environment &>/dev/null; then
    local state
    for state in is-enabled is-active; do
      systemctl --user "$state" --quiet voxtype || warn "voxtype is not ${state#is-} after setup, check: systemctl --user status voxtype"
    done
  fi
  # Lowers the output volume while voxtype records; voxtype's own ducking is off in config.toml. Idle until a recording.
  if [[ -e "$HOME/.config/systemd/user/voxtype-duck.service" ]]; then
    if systemctl --user show-environment &>/dev/null; then
      systemctl --user daemon-reload
      systemctl --user is-enabled --quiet voxtype-duck || systemctl --user enable --now voxtype-duck || warn "voxtype-duck did not enable, run later: systemctl --user enable --now voxtype-duck"
    else
      warn "User systemd not available, run after login: systemctl --user enable --now voxtype-duck"
    fi
  fi
  success "voxtype configured"
}

FIREFOX_EXTENSION_ID="voxcmd@oasis-dots"

# DesertFox's own bridge replaced the voxcmd Firefox extension. This undoes what the installer once put on a machine:
# the native-messaging manifest, the stowed host's dangling link, the installed xpi and the policy entry that loaded it.
# Quiet and idempotent, so the installer may run it every time. The paths and the sudo command are overridable so the
# test can run against a scratch directory without root. FIREFOX_POLICY_SUDO may be set to the empty string.
retire_voxcmd_firefox_extension() {
  local xpi_dest="${FIREFOX_EXTENSION_XPI_DEST:-/usr/share/oasis-dots/voxcmd-firefox.xpi}"
  local policies_file="${FIREFOX_POLICIES_FILE:-/etc/firefox/policies/policies.json}"
  local manifest="$HOME/.mozilla/native-messaging-hosts/voxcmd_firefox.json"
  local host="$HOME/.local/share/voxcmd/firefox-host"
  local -a sudo_cmd
  read -ra sudo_cmd <<<"${FIREFOX_POLICY_SUDO-sudo}"
  local retired=0

  if [[ -e "$manifest" || -L "$manifest" ]]; then
    rm -f "$manifest" && retired=1
  fi
  # Stow removes a link only while its package still holds the file, so the host's link outlives the deleted source.
  if [[ -L "$host" && ! -e "$host" ]]; then
    rm -f "$host" && retired=1
  fi
  if [[ -e "$xpi_dest" ]]; then
    "${sudo_cmd[@]}" rm -f "$xpi_dest" || return 1
    retired=1
  fi

  # Only a policies file that names the extension is read as JSON, so an unrelated broken file never fails the installer.
  if [[ -f "$policies_file" ]] && grep -qF "$FIREFOX_EXTENSION_ID" "$policies_file"; then
    require_cmd jq
    local trimmed policies_dir tmp
    if ! trimmed=$(jq --arg id "$FIREFOX_EXTENSION_ID" 'del(.policies.ExtensionSettings[$id]) | if .policies.ExtensionSettings == {} then del(.policies.ExtensionSettings) else . end' "$policies_file"); then
      warn "$policies_file is not valid JSON, leaving the old voxcmd Firefox policy entry alone"
      return 1
    fi
    policies_dir=$(dirname "$policies_file")
    tmp=$("${sudo_cmd[@]}" mktemp "$policies_dir/.policies.json.XXXXXX") || return 1
    if ! { printf '%s\n' "$trimmed" | "${sudo_cmd[@]}" tee "$tmp" >/dev/null &&
      "${sudo_cmd[@]}" chmod 644 "$tmp" &&
      "${sudo_cmd[@]}" mv -f "$tmp" "$policies_file"; }; then
      "${sudo_cmd[@]}" rm -f "$tmp"
      return 1
    fi
    retired=1
  fi
  ((retired)) && success "Retired the voxcmd Firefox extension: DesertFox's bridge replaces it, restart Firefox"
  return 0
}
