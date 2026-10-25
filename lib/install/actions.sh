#!/usr/bin/env bash
# Builds `act`, the action runner (home/actions), and links it onto PATH.

# Installs the crate under ~/.local/share/actions-rs and links ~/.local/bin/act to it, as `just voxcmd-build` does for voxcmd.
build_act() {
  if ! command -v cargo &>/dev/null; then
    warn "cargo not found, so act was not built; install Rust, then run: just act-build"
    return 0
  fi
  local root="${XDG_DATA_HOME:-$HOME/.local/share}/actions-rs"
  info "Building act..."
  cargo install --path "$DOTFILES_DIR/home/actions" --locked --root "$root" || return 1
  mkdir -p "$HOME/.local/bin"
  ln -sf "$root/bin/act" "$HOME/.local/bin/act"
  success "act installed: ~/.local/bin/act"
}
