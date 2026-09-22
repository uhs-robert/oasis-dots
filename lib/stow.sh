#!/usr/bin/env bash
# Stows dotfile packages and bootstraps shell/editor tooling.

# Symlinks one or more packages from home/ into ~; warns on conflicts.
do_stow() {
  cd "$DOTFILES_DIR" || return 1
  for pkg in "$@"; do
    if [[ ! -d "home/$pkg" ]]; then
      warn "Package '$pkg' not found, skipping"
      continue
    fi
    if stow "$pkg" 2>/dev/null; then
      success "Stowed $pkg"
    else
      warn "Stow conflict in $pkg, run 'stow --adopt $pkg' to resolve, then reset with git"
    fi
  done
}

prompt_optional() {
  echo ""
  info "Optional stow packages (Tab to select, Enter to confirm):"
  # shellcheck disable=SC2034  # consumed by install.sh
  mapfile -t SELECTED_OPTIONAL < <(
    read_ini_section stow.ini OPTIONAL | fzf --multi --prompt="packages> " --no-info
  )
}

bootstrap_tmuxifier() {
  info "Bootstrapping tmuxifier..."
  if [[ -d "$HOME/.tmuxifier" ]] || [[ -L "$HOME/.tmuxifier" ]] || [[ -e "$HOME/.tmuxifier" ]]; then
    warn "tmuxifier already present, skipping"
    return
  fi
  git clone https://github.com/jimeh/tmuxifier.git "$HOME/.tmuxifier"
  success "tmuxifier installed"
}

template_user_configs() {
  local active="$HOME/.config/hypr/monitors/active.conf"
  local default_layout="$HOME/.config/hypr/monitors/layouts/monitors-default.conf"
  if [[ -L "$active" && -f "$default_layout" ]]; then
    cp --remove-destination "$default_layout" "$active"
    success "Set default monitor layout (run toggle-monitor-layout.sh to switch)"
  fi
}

# Set NVIM_CONFIG_REPO to owner/name or a git URL to use a different config; an existing ~/.config/nvim is kept.
install_nvim_config() {
  local spec="${NVIM_CONFIG_REPO:-$GITHUB_ORG/neovim}"
  local dest target="$HOME/.config/nvim"
  dest="$REPOS_DIR/$(basename "$spec" .git)"
  if [[ -e "$target" || -L "$target" ]]; then
    warn "$target already exists, skipping Neovim config"
    return
  fi
  ensure_repo "$spec" personal
  [[ -d "$dest" ]] || return 0
  mkdir -p "$HOME/.config"
  ln -s "$dest" "$target"
  success "Linked $dest → $target"
}

bootstrap_neovim() {
  info "Bootstrapping Neovim plugins..."
  if ! command -v nvim &>/dev/null; then
    warn "nvim not in PATH, skipping plugin bootstrap"
    return
  fi
  nvim --headless "+Lazy! sync" +qa 2>/dev/null || true
  success "Neovim plugins synced"
}

setup_root_symlinks() {
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
