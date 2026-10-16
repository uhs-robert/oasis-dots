#!/usr/bin/env bash
# Language runtimes and developer tooling: fnm/pnpm/bun/go/deno, tmuxifier, the git identity, and the Neovim config and plugins.

install_devtool_nodejs() {
  if command -v fnm &>/dev/null; then
    warn "fnm already present, skipping"
    return
  fi
  info "Installing fnm (node version manager)..."
  if command -v cargo &>/dev/null; then
    cargo install fnm
  else
    curl -fsSL https://fnm.vercel.app/install | bash --no-use
  fi
  success "fnm installed, run: fnm install --lts"
}

install_devtool_pnpm() {
  if command -v pnpm &>/dev/null; then
    warn "pnpm already present, skipping"
    return
  fi
  info "Installing pnpm..."
  curl -fsSL https://get.pnpm.io/install.sh | sh -
  success "pnpm installed"
}

install_devtool_bun() {
  if command -v bun &>/dev/null; then
    warn "bun already present, skipping"
    return
  fi
  info "Installing bun..."
  curl -fsSL https://bun.sh/install | bash
  success "bun installed"
}

install_devtool_go() {
  if command -v go &>/dev/null; then
    warn "go already present, skipping"
    return
  fi
  info "Installing Go..."
  sudo pacman -S --needed --noconfirm go
  success "Go installed"
}

install_devtool_deno() {
  if command -v deno &>/dev/null; then
    warn "deno already present, skipping"
    return
  fi
  info "Installing deno..."
  curl -fsSL https://deno.land/install.sh | sh
  success "deno installed"
}

# Presents an fzf picker of optional runtimes and dispatches to the right installer.
install_dev_tools() {
  echo ""
  if [[ $OPT_YES -eq 1 ]]; then
    info "Optional developer runtimes: none selected (--yes)"
    return
  fi
  info "Optional developer runtimes (Tab to select, Enter to confirm):"
  mapfile -t selected < <(
    read_ini_section devtools.ini TOOLS | fzf --multi --prompt="dev tools> " --no-info
  )
  [[ ${#selected[@]} -eq 0 ]] && return
  for tool in "${selected[@]}"; do
    case "$tool" in
    nodejs) install_devtool_nodejs ;;
    pnpm) install_devtool_pnpm ;;
    bun) install_devtool_bun ;;
    go) install_devtool_go ;;
    deno) install_devtool_deno ;;
    *) warn "Unknown dev tool: $tool, skipping" ;;
    esac
  done
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
