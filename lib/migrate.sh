#!/usr/bin/env bash
# One-time migrations for installs made before a layout change. Each is idempotent: on a migrated machine it finds nothing and changes nothing.

# Runs the command, or only prints it when MIGRATE_DRY_RUN=1.
_migrate_run() {
  if [[ "${MIGRATE_DRY_RUN:-0}" -eq 1 ]]; then
    info "would run: $*"
  else
    "$@"
  fi
}

# Paths under ~/.config/systemd that resolve into a package of the repo, whether the symlink is the path itself or one of its parents;
# systemd ignores such drop-in and .wants directories.
_folded_systemd_links() {
  local base="$HOME/.config/systemd" path target packages_dir
  packages_dir=$(readlink -f "$DOTFILES_DIR/home")
  while IFS= read -r path; do
    [[ -d "$path" ]] || continue
    target=$(readlink -f "$path")
    [[ "$target" == "$packages_dir"/*/.config/systemd* ]] && printf '%s\n' "$path"
  done < <(
    printf '%s\n' "$base" "$base/user"
    find "$base/user" -maxdepth 1 -type l 2>/dev/null
  )
}

# Untracked files (ignored included) under the packages' systemd trees: what systemctl and voxtype wrote into the repo while it was folded.
_generated_systemd_files() {
  local pkg
  for pkg in "${NO_FOLD_PACKAGES[@]}"; do
    [[ -d "$DOTFILES_DIR/home/$pkg/.config/systemd" ]] || continue
    git -C "$DOTFILES_DIR" ls-files -o -- "home/$pkg/.config/systemd"
  done
}

# Moves a folded ~/.config/systemd out of the repo, which the installer also does before stowing: unstow, move the generated files into ~, stow again unfolded.
migrate_unfold_systemd() {
  local link target pkg rel dest packages_dir
  packages_dir=$(readlink -f "$DOTFILES_DIR/home")
  local -a pkgs=()
  while IFS= read -r link; do
    target=$(readlink -f "$link")
    pkg=${target#"$packages_dir"/}
    pkgs+=("${pkg%%/*}")
    info "Folded: $link -> $target"
  done < <(_folded_systemd_links)

  if [[ ${#pkgs[@]} -gt 0 ]]; then
    mapfile -t pkgs < <(printf '%s\n' "${pkgs[@]}" | sort -u)
    _migrate_run stow_packages -D "${pkgs[@]}"
  fi

  while IFS= read -r rel; do
    dest="$HOME/${rel#home/*/}"
    if [[ ${#pkgs[@]} -eq 0 && (-e "$dest" || -L "$dest") ]]; then
      warn "Generated $rel already exists at $dest, leaving the repo copy for you to delete"
      continue
    fi
    info "Generated file in the repo: $rel"
    _migrate_run mkdir -p "$(dirname "$dest")"
    _migrate_run mv "$DOTFILES_DIR/$rel" "$dest"
  done < <(_generated_systemd_files)

  [[ ${#pkgs[@]} -gt 0 ]] && _migrate_run stow_packages -S "${pkgs[@]}"
  return 0
}

# voxtype.service comes from `voxtype setup systemd`, not the repo; it must be a real file and enabled, as nothing else autostarts it.
_migrate_voxtype_unit() {
  local unit="$HOME/.config/systemd/user/voxtype.service"
  command -v voxtype &>/dev/null || return 0
  if ! systemctl --user show-environment &>/dev/null; then
    warn "User systemd not available, run after login: just migrate-systemd"
    return 0
  fi

  if [[ ! -e "$unit" || -L "$unit" ]]; then
    info "voxtype.service is missing or a repo symlink"
    [[ -L "$unit" ]] && _migrate_run rm -f "$unit"
    _migrate_run voxtype setup systemd
  fi
  [[ "${MIGRATE_DRY_RUN:-0}" -eq 1 && ! -e "$unit" ]] && return 0
  if ! systemctl --user is-enabled --quiet voxtype; then
    _migrate_run systemctl --user daemon-reload
    _migrate_run systemctl --user enable voxtype
  fi
  systemctl --user is-active --quiet voxtype || _migrate_run systemctl --user start voxtype
}

# Unfolds the systemd packages and enables voxtype; `--dry-run` only reports. Run on its own with `just migrate-systemd`.
migrate_systemd() {
  [[ "${1:-}" == --dry-run ]] && MIGRATE_DRY_RUN=1
  info "Checking the systemd packages for the folded layout..."
  migrate_unfold_systemd
  _migrate_voxtype_unit
  success "systemd migration checked"
}
