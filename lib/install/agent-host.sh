#!/usr/bin/env bash
# The agent-host profile (`install.sh --agent-host`): a headless machine that runs agent sessions and the plans board.
# It starts no desktop service at boot. Only plans-serve is enabled, through a drop-in, so a laptop's stowed unit stays as is.

AGENT_HOST_DROPIN_SRC="$DOTFILES_DIR/lib/install/agent-host/plans-serve.conf"

setup_agent_host() {
  local config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
  local unit_dir="$config_home/systemd/user"
  local dropin_dir="$unit_dir/plans-serve.service.d"

  # Linger keeps the user manager, and so plans-serve, running with no login. Setting it again changes nothing.
  loginctl enable-linger "$USER"

  # --server stows no plans package, and the drop-in only adds to its unit.
  [[ -e $unit_dir/plans-serve.service ]] || do_stow plans

  if ! cmp -s "$AGENT_HOST_DROPIN_SRC" "$dropin_dir/agent-host.conf"; then
    mkdir -p "$dropin_dir"
    cp "$AGENT_HOST_DROPIN_SRC" "$dropin_dir/agent-host.conf"
    systemctl --user daemon-reload
  fi

  # The service does not see GITHUB_DIR, and this file replaces the default roots, so it names them. An edited file stays.
  local roots="$config_home/plans/roots"
  if [[ ! -e $roots ]]; then
    mkdir -p "$(dirname "$roots")"
    printf '%s\n' "$GITHUB_DIR" "$DOTFILES_DIR" >"$roots"
  fi

  systemctl --user enable plans-serve.service
  success "Agent host: plans-serve starts at boot (linger is on); no desktop service is enabled"
  info "Next: write ${config_home}/plans/remote.json (this host's MagicDNS name and tailnet login), then run:"
  info "  tailscale serve --bg --https=443 http://127.0.0.1:8765"
  info "Then run 'just agent-host-seed <this-host>' on the laptop"
}
