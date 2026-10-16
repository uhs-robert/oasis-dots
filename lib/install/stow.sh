#!/usr/bin/env bash
# Stows dotfile packages.

# systemd ignores drop-in (.d) and .wants directories that are symlinks, and `systemctl enable` writes into them.
# Stow folds a directory missing from ~ into one symlink, so these packages are stowed with --no-folding.
NO_FOLD_PACKAGES=(systemd calendar)

# Runs `stow <mode>` (-S, -D or -R) on each package, unfolding the NO_FOLD_PACKAGES.
stow_packages() {
  local mode="$1" pkg status=0
  local -a args
  shift
  for pkg in "$@"; do
    args=(-d "$DOTFILES_DIR/home" -t "$HOME" "$mode")
    [[ " ${NO_FOLD_PACKAGES[*]} " == *" $pkg "* ]] && args+=(--no-folding)
    stow "${args[@]}" "$pkg" || status=1
  done
  return $status
}

# Symlinks one or more packages from home/ into ~; warns on conflicts.
do_stow() {
  cd "$DOTFILES_DIR" || return 1
  for pkg in "$@"; do
    if [[ ! -d "home/$pkg" ]]; then
      warn "Package '$pkg' not found, skipping"
      continue
    fi
    if stow_packages -S "$pkg"; then
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
