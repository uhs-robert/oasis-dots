#!/usr/bin/env bash
# Clones external repos and links each into repos/, the one path dotfiles reference.

# Maps owner/name to a clone URL; full URLs pass through.
_repo_url() {
  local spec="$1"
  if [[ "$spec" == *:* ]]; then
    echo "$spec"
  elif [[ "${OPT_DEV:-0}" -eq 1 && "${spec%%/*}" == "$GITHUB_ORG" ]]; then
    echo "git@github.com:$spec.git"
  else
    echo "https://github.com/$spec.git"
  fi
}

# Makes repos/<name> resolve to a checkout, reusing one under $GITHUB_DIR when present.
ensure_repo() {
  local spec="$1" subdir="$2" name link dev
  name="$(basename "$spec" .git)"
  link="$REPOS_DIR/$name"
  dev="$GITHUB_DIR/$subdir/$name"
  mkdir -p "$REPOS_DIR"

  [[ -d "$link" && ! -L "$link" ]] && return 0
  if [[ ! -d "$dev" && "${OPT_DEV:-0}" -eq 1 ]] && ! git clone "$(_repo_url "$spec")" "$dev"; then
    warn "Failed to clone $spec"
    return 0
  fi
  if [[ -d "$dev" ]]; then
    ln -sfn "$dev" "$link"
    success "Linked repos/$name → $dev"
  elif rm -f "$link" && git clone "$(_repo_url "$spec")" "$link"; then
    success "Cloned repos/$name"
  else
    warn "Failed to clone $spec"
  fi
}

clone_repos() {
  info "Setting up external repos → $REPOS_DIR"
  local section spec
  for section in TOOLS PERSONAL; do
    while IFS= read -r spec; do
      ensure_repo "$spec" "${section,,}"
    done < <(read_ini_section repos.ini "$section")
  done
  mkdir -p "$(dirname "$REPOS_LINK")"
  ln -sfn "$REPOS_DIR" "$REPOS_LINK"
  link_keeptabs
}

# keeptabs ships its own Makefile; link rather than copy so the checkout stays live.
link_keeptabs() {
  local dir="$REPOS_DIR/keeptabs"
  [[ -f "$dir/Makefile" ]] || return 0
  if make -s -C "$dir" link; then
    success "Linked keeptabs into ~/.local"
  else
    warn "Failed to link keeptabs"
  fi
}
