#!/usr/bin/env bash
# Build a throwaway Quickshell test bar from branches, swap the live bar to it, and restore the stowed bar.
set -euo pipefail

repo=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
qs_rel=home/quickshell/.config/quickshell
bars="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/test-bars"
ipc="$HOME/.config/hypr/scripts/qs-ipc"

die() {
  echo "test-bar: $*" >&2
  exit 1
}

require_unlocked() {
  pgrep -x qs >/dev/null || return 0
  local state
  state=$(timeout 3 "$ipc" call lock state 2>/dev/null || true)
  [[ $state == unlocked ]] || die "lock state is '${state:-unknown}'; Quickshell runs the lock screen, so it is not restarted until it reports 'unlocked'"
}

# Launch through Hyprland so qs does not inherit this shell's TMUX environment.
launch() {
  pkill -x qs || true
  for _ in $(seq 20); do pgrep -x qs >/dev/null || break; sleep 0.2; done
  hyprctl dispatch "hl.dsp.exec_cmd('$1')" >/dev/null
  sleep 6
}

verify() {
  local log=$1
  pgrep -af '^qs ' || die "qs is not running after launch; read the log with: $log"
  local errors
  errors=$($log 2>&1 | grep -E 'ERROR|TypeError|ReferenceError|Binding loop' || true)
  [[ -z $errors ]] || {
    echo "$errors" >&2
    die "the bar started but logged errors (above)"
  }
  $log 2>&1 | grep -q 'Configuration Loaded' || die "no 'Configuration Loaded' in the log yet"
  echo "test-bar: loaded cleanly"
}

copy_assets() {
  local dest=$1 path
  while read -r path; do
    [[ $path == *__pycache__* ]] && continue
    mkdir -p "$(dirname "$dest/$path")"
    cp -a "$repo/$path" "$dest/$path"
  done < <(git -C "$repo" status --short --ignored "$qs_rel" | awk '$1 == "!!" { sub(/\/$/, "", $2); print $2 }')
}

build() {
  local name=$1
  shift
  (($# > 0)) || die "usage: test-bar.sh build <name> <branch>..."
  local dir="$bars/$name"
  [[ -e $dir ]] && die "$dir exists; remove it first with: test-bar.sh remove $name"
  git -C "$repo" fetch -q origin || true
  git -C "$repo" worktree add -q --detach "$dir" origin/main
  local branch
  for branch in "$@"; do
    git -C "$dir" merge -q --no-edit "$branch" || die "merging $branch conflicted in $dir; resolve it there or drop the branch"
  done
  copy_assets "$dir"
  (cd "$dir" && just check >/dev/null) || die "just check fails on the combined build in $dir"
  echo "test-bar: built $dir from $*"
}

case ${1:-} in
  build)
    shift
    build "$@"
    ;;
  swap)
    dir="$bars/${2:?usage: test-bar.sh swap <name>}"
    [[ -d $dir ]] || die "no test bar at $dir"
    require_unlocked
    launch "qs -n -p $dir/$qs_rel"
    verify "qs log -p $dir/$qs_rel"
    ;;
  up)
    name=${2:?usage: test-bar.sh up <name> <branch>...}
    shift 2
    build "$name" "$@"
    "$0" swap "$name"
    ;;
  restore)
    require_unlocked
    launch "qs -n"
    verify "qs log"
    ;;
  remove)
    dir="$bars/${2:?usage: test-bar.sh remove <name>}"
    pgrep -af "^qs .*-p $dir" >/dev/null && die "that test bar is running; run test-bar.sh restore first"
    git -C "$repo" worktree remove --force "$dir"
    git -C "$repo" worktree prune
    echo "test-bar: removed $dir"
    ;;
  *)
    die "usage: test-bar.sh {up <name> <branch>...|build <name> <branch>...|swap <name>|restore|remove <name>}"
    ;;
esac
