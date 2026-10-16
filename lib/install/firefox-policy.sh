#!/usr/bin/env bash
# Installs voxcmd's signed Firefox extension through an enterprise policy, so it survives restarts without a manual install.

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
