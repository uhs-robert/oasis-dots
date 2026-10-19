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

# Ignored files under the packages' systemd trees: what systemctl and voxtype wrote into the repo while it was folded.
# Only ignored ones, so a unit being written but not yet committed stays in the checkout.
_generated_systemd_files() {
  local pkg
  for pkg in "${NO_FOLD_PACKAGES[@]}"; do
    [[ -d "$DOTFILES_DIR/home/$pkg/.config/systemd" ]] || continue
    git -C "$DOTFILES_DIR" ls-files -o -i --exclude-standard -- "home/$pkg/.config/systemd"
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

# voxtype-duck.service ducks the output sink, and config.toml now turns voxtype's own per-app ducking off. voxtype reads
# config.toml only at start, so it restarts BEFORE the follower is enabled: the other way round, one recording would duck
# twice (30% of 30%). Done once, when the follower is not yet enabled, so a later run never cuts a recording off.
_migrate_voxtype_duck() {
  command -v voxtype &>/dev/null || return 0
  [[ -e "$HOME/.config/systemd/user/voxtype-duck.service" ]] || return 0
  systemctl --user show-environment &>/dev/null || return 0
  systemctl --user is-enabled --quiet voxtype-duck && return 0
  info "voxtype-duck is not enabled"
  _migrate_run systemctl --user daemon-reload
  _migrate_run systemctl --user try-restart voxtype
  _migrate_run systemctl --user enable --now voxtype-duck
}

# Unfolds the systemd packages and enables voxtype; `--dry-run` only reports. Run on its own with `just migrate-systemd`.
migrate_systemd() {
  [[ "${1:-}" == --dry-run ]] && MIGRATE_DRY_RUN=1
  info "Checking the systemd packages for the folded layout..."
  migrate_unfold_systemd
  _migrate_voxtype_unit
  _migrate_voxtype_duck
  success "systemd migration checked"
}

# The gitignored, user-imported skin assets, relative to a skin's folder under skins/; the Quickshell .gitignore lists the same ones.
_LOCK_ASSET_DIRS=(ocarina/audio ff7/audio mgs2/audio goldeneye/audio goldeneye/frames)

# Moves one file or symlink from lock/ to the same place under features/lock/, unless something is already there.
# A relative symlink is rewritten so it still resolves to the same place from its new location;
# a target inside a migrated asset dir is itself moving, so the link follows it to features/lock/.
_migrate_lock_asset() {
  local qs_dir=$1 file=$2 rel dest
  rel=${file#"$qs_dir/lock/"}
  dest="$qs_dir/features/lock/$rel"
  if [[ -e "$dest" || -L "$dest" ]]; then
    warn "Not moving lock/$rel: features/lock/$rel already exists, delete whichever copy you do not want"
    return 0
  fi
  info "Moving lock/$rel to features/lock/$rel"
  _migrate_run mkdir -p "$(dirname "$dest")"
  _migrate_run mv "$file" "$dest"
  [[ "${MIGRATE_DRY_RUN:-0}" -eq 1 ]] && return 0
  local target resolved old_root asset
  if [[ -L "$dest" ]] && target=$(readlink "$dest") && [[ "$target" != /* ]]; then
    resolved=$(realpath -m "$(dirname "$file")/$target")
    old_root=$(realpath -m "$qs_dir/lock")
    for asset in "${_LOCK_ASSET_DIRS[@]}"; do
      [[ "$resolved" == "$old_root/skins/$asset"/* ]] && resolved="$(realpath -m "$qs_dir/features/lock")/${resolved#"$old_root"/}"
    done
    ln -sfn "$(realpath -m --relative-to="$(dirname "$dest")" "$resolved")" "$dest"
  fi
}

# Moves imported lock-skin assets from the old top-level lock/ into features/lock/ (moved there by the Quickshell refactor 4.1);
# git leaves ignored files behind, and the QML reads only the new paths. Never overwrites: a file already at the new path stays,
# and the old copy is reported and left for the user. $1 is the Quickshell config dir, for the tests.
migrate_quickshell_lock_assets() {
  local qs_dir=${1:-$DOTFILES_DIR/home/quickshell/.config/quickshell} asset old_dir file
  for asset in "${_LOCK_ASSET_DIRS[@]}"; do
    old_dir="$qs_dir/lock/skins/$asset"
    [[ -d "$old_dir" || -L "$old_dir" ]] || continue
    # A symlinked asset dir moves as the link itself and is never followed; the find below would also list it, but not descend.
    while IFS= read -r -d '' file; do
      _migrate_lock_asset "$qs_dir" "$file"
    done < <(find "$old_dir" \( -type f -o -type l \) -print0)
    [[ "${MIGRATE_DRY_RUN:-0}" -eq 1 ]] && continue
    # Removes emptied directories only, up through lock/ itself.
    [[ ! -d "$old_dir" ]] || find "$old_dir" -depth -type d -empty -delete
    (cd "$qs_dir" && rmdir -p --ignore-fail-on-non-empty "lock/skins/${asset%%/*}" 2>/dev/null) || true
  done
  return 0
}

# Quickshell used to keep the notification Do Not Disturb flag and the Claude usage "warned" marker per checkout, under
# <state>/by-shell/<id>/ (Quickshell.stateDir); both now live in <state>/ with the rest. Copies the newest non-empty file of each
# into <state>/ unless <state>/ already holds a newer one, then deletes by-shell. Newest by mtime because the id is a hash of the
# shell.qml path, which the shell cannot derive, so the newest copy may come from a worktree or shadow run; accepted.
# Meant to run twice around the bar restart: a bar still on the old code keeps writing into by-shell, so while any bar runs by-shell
# is kept and the copy repeats (newest wins, so a rerun picks up what was written since).
# Only a run with no bar up deletes it. Detecting an old-code bar is not
# possible from its command line (`qs -n` names no config), so any running bar counts. $1 is the Quickshell state dir, for the tests.
migrate_quickshell_state() {
  local state=${1:-${XDG_STATE_HOME:-$HOME/.local/state}/quickshell} by name newest
  by=$state/by-shell
  [[ -d "$by" ]] || return 0
  for name in notifications.json claude_usage_warned.json; do
    newest=$(find "$by" -mindepth 2 -maxdepth 2 -name "$name" -type f -size +0 -printf '%T@\t%p\n' | awk -F'\t' '$1 > newest { newest = $1; path = $2 } END { print path }')
    [[ -n "$newest" ]] || continue
    [[ ! -e "$state/$name" || "$newest" -nt "$state/$name" ]] || continue
    _migrate_run mkdir -p "$state"
    _migrate_run cp -p -- "$newest" "$state/$name"
    info "Copied $newest to $state/$name"
  done
  if pgrep -x 'qs|quickshell' >/dev/null; then
    warn "A Quickshell bar is running and may still write into $by; kept it. A rerun with the bar up still copies newer files; to delete it, stop the bar, rerun, then start the bar."
    return 0
  fi
  [[ "$by" == */quickshell/by-shell ]] || return 0
  _migrate_run rm -rf -- "$by"
  return 0
}

# Quickshell's Typing settings (start mode, remember query) used to be saved as input.json, a name shared with Hyprland's
# input.json in the hypr state dir; they now save as typing.json. Copies the old file once and leaves it: a bar still on the old
# code keeps reading it, and a rollback finds it. Never overwrites. $1 is the Quickshell state dir, for the tests.
migrate_quickshell_input() {
  local state=${1:-${XDG_STATE_HOME:-$HOME/.local/state}/quickshell}
  [[ -f "$state/input.json" ]] || return 0
  [[ ! -e "$state/typing.json" && ! -L "$state/typing.json" ]] || return 0
  # install.sh runs under set -e, and a Typing setting is not worth blocking the install.
  _migrate_run cp -p -- "$state/input.json" "$state/typing.json" || {
    warn "Could not copy $state/input.json to typing.json; the Typing settings start at their defaults"
    return 0
  }
  info "Copied $state/input.json to $state/typing.json"
}
