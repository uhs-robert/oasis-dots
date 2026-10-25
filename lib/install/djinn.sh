#!/usr/bin/env bash
# Builds `oasis-djinn`, the action runner (home/oasis-djinn), and links it onto PATH.

# Installs the crate under ~/.local/share/oasis-djinn-rs and links ~/.local/bin/oasis-djinn to it, as `just voxcmd-build` does for voxcmd.
build_djinn() {
  if ! command -v cargo &>/dev/null; then
    warn "cargo not found, so oasis-djinn was not built; install Rust, then run: just djinn-build"
    return 0
  fi
  local root="${XDG_DATA_HOME:-$HOME/.local/share}/oasis-djinn-rs"
  info "Building oasis-djinn..."
  cargo install --path "$DOTFILES_DIR/home/oasis-djinn" --locked --root "$root" || return 1
  mkdir -p "$HOME/.local/bin"
  ln -sf "$root/bin/oasis-djinn" "$HOME/.local/bin/oasis-djinn"
  success "oasis-djinn installed: ~/.local/bin/oasis-djinn"
}
