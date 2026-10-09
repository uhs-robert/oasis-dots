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
    if stow "$pkg"; then
      success "Stowed $pkg"
    else
      warn "Could not stow $pkg: move the conflicting files aside, then re-run 'just stow $pkg'"
    fi
  done
}

# Copies each *.template.* in the given packages to its generated name when absent.
seed_generated_defaults() {
  local pkg tpl dest
  for pkg in "$@"; do
    [[ -d "$DOTFILES_DIR/home/$pkg" ]] || continue
    while IFS= read -r tpl; do
      dest="$HOME/${tpl#"$DOTFILES_DIR/home/$pkg/"}"
      dest="${dest/.template./.}"
      [[ -e "$dest" ]] && continue
      # A link left by stow before the file became generated would block cp.
      [[ -L "$dest" ]] && rm -f "$dest"
      mkdir -p "$(dirname "$dest")" && cp "$tpl" "$dest" && info "Seeded default ${dest##*/}"
    done < <(find "$DOTFILES_DIR/home/$pkg" -name '*.template.*' -type f)
  done
}

prompt_optional() {
  echo ""
  if [[ $OPT_YES -eq 1 ]]; then
    info "Optional stow packages: none selected (--yes)"
    return
  fi
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

# Writes ~/.config/git/identity when absent; the tracked git config includes it.
setup_git_identity() {
  local file="$HOME/.config/git/identity" name email
  [[ -e "$file" ]] && return
  if [[ $OPT_YES -eq 1 ]]; then
    warn "No git identity at $file, set user.name and user.email there"
    return
  fi
  read -rp "Git user.name (blank to skip): " name
  [[ -n "$name" ]] || return
  read -rp "Git user.email: " email
  [[ -n "$email" ]] || return
  mkdir -p "$(dirname "$file")"
  printf '[user]\n\tname = %s\n\temail = %s\n' "$name" "$email" >"$file"
  success "Wrote git identity to $file"
}

# Set NVIM_CONFIG_REPO to owner/name or a git URL to use a different config; an existing ~/.config/nvim is kept.
install_nvim_config() {
  local spec="${NVIM_CONFIG_REPO:-$GITHUB_ORG/neovim}"
  local dest target="$HOME/.config/nvim"
  dest="$REPOS_DIR/$(basename "$spec" .git)"
  if [[ -e "$target" ]]; then
    warn "$target already exists, skipping Neovim config"
    return
  fi
  # A dangling link is left over from an older layout, never a config worth keeping.
  if [[ -L "$target" ]]; then
    rm -f "$target"
    warn "Replaced dangling $target"
  fi
  ensure_repo "$spec" personal
  [[ -d "$dest" ]] || return 0
  enable_repo_hooks
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
