#!/usr/bin/env bash
# Voice input: voxtype setup, plus voxcmd's Firefox host and the signed extension installed through an enterprise policy.

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

# Registers voxcmd's Firefox host with Firefox. The manifest needs the host's absolute path, so it cannot be a stowed
# file. Without the stowed voxcmd package there is no host to register: silent from the installer, a warning from `just`.
register_firefox_host() {
  local host="$HOME/.local/share/voxcmd/firefox-host"
  local manifest="$HOME/.mozilla/native-messaging-hosts/voxcmd_firefox.json"
  if [[ ! -x "$host" ]]; then
    [[ "${1:-}" == --quiet ]] || warn "voxcmd's Firefox host is not stowed ($host), run: just stow voxcmd"
    return 0
  fi
  if [[ "$host" == *[\"\\]* ]]; then
    warn "Not registering the Firefox host: its path has a quote or backslash"
    return 1
  fi
  local wanted
  wanted=$(printf '{\n  "name": "voxcmd_firefox",\n  "description": "voxcmd tab control",\n  "path": "%s",\n  "type": "stdio",\n  "allowed_extensions": ["voxcmd@oasis-dots"]\n}\n' "$host")
  if [[ "$(cat "$manifest" 2>/dev/null)" == "$wanted" ]]; then
    info "Firefox host already registered"
    return 0
  fi
  mkdir -p "$(dirname "$manifest")"
  printf '%s\n' "$wanted" >"$manifest"
  success "Firefox host registered: load extras/voxcmd-firefox in Firefox (see its README)"
}

FIREFOX_EXTENSION_ID="voxcmd@oasis-dots"

# The paths and the sudo command are overridable so the test can run against a scratch directory without root.
# FIREFOX_POLICY_SUDO may be set to the empty string.
install_firefox_extension_policy() {
  local quiet=0
  [[ "${1:-}" == --quiet ]] && quiet=1
  local source_xpi="$DOTFILES_DIR/extras/voxcmd-firefox.xpi"
  local xpi_dest="${FIREFOX_EXTENSION_XPI_DEST:-/usr/share/oasis-dots/voxcmd-firefox.xpi}"
  local policies_file="${FIREFOX_POLICIES_FILE:-/etc/firefox/policies/policies.json}"
  local distribution_policies="${FIREFOX_DISTRIBUTION_POLICIES:-/usr/lib/firefox/distribution/policies.json}"
  local -a sudo_cmd
  read -ra sudo_cmd <<<"${FIREFOX_POLICY_SUDO-sudo}"

  if ! command -v firefox &>/dev/null; then
    ((quiet)) || info "Firefox is not installed, skipping the voxcmd extension"
    return 0
  fi
  if [[ ! -x "$HOME/.local/share/voxcmd/firefox-host" ]]; then
    ((quiet)) || warn "voxcmd is not stowed, so the Firefox extension has no host to talk to, run: just stow voxcmd"
    return 0
  fi
  if [[ ! -f "$source_xpi" ]]; then
    ((quiet)) || warn "No signed extension at $source_xpi, run: just sign-firefox-extension"
    return 0
  fi
  require_cmd jq

  # Firefox reads one policies file and does not merge, so an existing distribution file is shadowed by ours.
  if [[ -f "$distribution_policies" ]]; then
    warn "$distribution_policies exists and is ignored once $policies_file does; merge its policies there first"
    return 1
  fi

  local policies_json='{}'
  if [[ -e "$policies_file" ]]; then
    policies_json=$(<"$policies_file")
    if ! jq -e . >/dev/null 2>&1 <<<"$policies_json"; then
      warn "$policies_file is not valid JSON, leaving it alone"
      return 1
    fi
  fi
  local entry
  entry=$(jq -n --arg url "file://$xpi_dest" '{installation_mode: "normal_installed", install_url: $url}')

  local xpi_current=0 policy_current=0
  cmp -s "$source_xpi" "$xpi_dest" && xpi_current=1
  jq -e --arg id "$FIREFOX_EXTENSION_ID" --argjson entry "$entry" '.policies.ExtensionSettings[$id] == $entry' >/dev/null <<<"$policies_json" && policy_current=1
  if ((xpi_current && policy_current)); then
    info "Firefox extension policy already current"
    return 0
  fi

  if ((! xpi_current)); then
    "${sudo_cmd[@]}" install -Dm644 "$source_xpi" "$xpi_dest" || return 1
  fi
  if ((! policy_current)); then
    local merged policies_dir tmp
    merged=$(jq --arg id "$FIREFOX_EXTENSION_ID" --argjson entry "$entry" '.policies.ExtensionSettings[$id] = $entry' <<<"$policies_json") || return 1
    policies_dir=$(dirname "$policies_file")
    "${sudo_cmd[@]}" install -d "$policies_dir" || return 1
    tmp=$("${sudo_cmd[@]}" mktemp "$policies_dir/.policies.json.XXXXXX") || return 1
    if ! { printf '%s\n' "$merged" | "${sudo_cmd[@]}" tee "$tmp" >/dev/null &&
      "${sudo_cmd[@]}" chmod 644 "$tmp" &&
      "${sudo_cmd[@]}" mv -f "$tmp" "$policies_file"; }; then
      "${sudo_cmd[@]}" rm -f "$tmp"
      return 1
    fi
  fi
  success "Firefox extension policy installed: restart Firefox to load voxcmd"
}
