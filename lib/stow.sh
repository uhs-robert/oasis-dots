#!/usr/bin/env bash
# Stows dotfile packages and bootstraps shell/editor tooling.

# Symlinks one or more packages from home/ into ~; warns on conflicts.
do_stow() {
  cd "$DOTFILES_DIR"
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
  mapfile -t SELECTED_OPTIONAL < <(
    read_ini_section stow.ini OPTIONAL | fzf --multi --prompt="packages> " --no-info
  )
}

bootstrap_omz() {
  info "Bootstrapping Oh My Zsh..."
  if [[ -d "$HOME/.oh-my-zsh" ]]; then
    warn "Oh My Zsh already present, skipping"
    return
  fi
  RUNZSH=no KEEP_ZSHRC=yes \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  success "Oh My Zsh installed"
}

bootstrap_tmuxifier() {
  info "Bootstrapping tmuxifier..."
  if [[ -d "$HOME/.tmuxifier" ]]; then
    warn "tmuxifier already present, skipping"
    return
  fi
  git clone https://github.com/jimeh/tmuxifier.git "$HOME/.tmuxifier"
  success "tmuxifier installed"
}

template_user_configs() {
  local src_home="/home/roberth"
  [[ "$HOME" == "$src_home" ]] && return
  info "Replacing hardcoded home paths in user configs..."
  local files=(
    "$HOME/.codex/config.toml"
    "$HOME/.config/yazi/keymap.toml"
  )
  for f in "${files[@]}"; do
    [[ -f "$f" ]] || continue
    sed -i "s|$src_home|$HOME|g" "$f"
    success "Templated $(basename "$(dirname "$f")")/$(basename "$f")"
  done

  local active="$HOME/.config/hypr/monitors/active.conf"
  local default_layout="$HOME/.config/hypr/monitors/layouts/monitors-default.conf"
  if [[ -L "$active" && -f "$default_layout" ]]; then
    cp --remove-destination "$default_layout" "$active"
    success "Set default monitor layout (run toggle-monitor-layout.sh to switch)"
  fi
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

  sudo ln -sf "$HOME/.zshrc"       /root/.zshrc
  sudo ln -sf "$HOME/.oh-my-zsh"   /root/.oh-my-zsh
  sudo ln -sf "$HOME/.config/nvim" /root/.config/nvim

  for item in flavors plugins keymap.toml yazi.toml; do
    sudo ln -sf "$HOME/.config/yazi/$item" "/root/.config/yazi/$item"
  done

  sudo tee /root/.config/yazi/theme.toml > /dev/null <<'EOF'
[flavor]
dark = "oasis-sol-dark"
EOF

  success "Root symlinks set"
}
