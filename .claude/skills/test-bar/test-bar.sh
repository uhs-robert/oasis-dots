#!/usr/bin/env bash
# Build a throwaway Quickshell test bar from branches, swap the live bar to it, and restore the stowed bar.
set -euo pipefail

repo=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
qs_rel=home/quickshell/.config/quickshell
bars="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/test-bars"
ipc="$repo/home/hypr/.config/hypr/scripts/qs-ipc"
hypr_link="$HOME/.config/hypr"
hypr_rel=home/hypr/.config/hypr
hypr_orig="$bars/.hypr_orig"
hypr_bar="$bars/.hypr_bar"

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

# The owner may be mid-test on another bar; refuse to replace it unless asked to.
guard_live_bar() {
  local name=$1 replace=$2 live
  live=$(pgrep -af "^qs .*-p $bars/" | sed -n "s|.*-p $bars/\([^/]*\)/.*|\1|p" | head -n 1)
  [[ -z $live || $live == "$name" || $replace == 1 ]] && return 0
  die "test bar '$live' is running and the owner may be testing it; include its branches ($(tr '\n' ' ' <"$bars/$live.branches" 2>/dev/null)) in this bar, or pass --replace once the owner agrees"
}

# Launch through Hyprland so qs does not inherit this shell's TMUX environment.
launch() {
  pkill -x qs || true
  for _ in $(seq 20); do pgrep -x qs >/dev/null || break; sleep 0.2; done
  hyprctl dispatch "hl.dsp.exec_cmd('$1')" >/dev/null
  sleep 6
}

fail_pattern='ERROR|TypeError|ReferenceError|Binding loop|is not a type|Could not set initial property|File not found|is not installed|Cannot assign'
# shellcheck disable=SC2016
load_hint='a QML type or file failed to load; for `X is not a type` on a folder loaded by URL, add `import "<folder>"` to the loader file (see #531)'

verify() {
  local log=$1
  pgrep -af '^qs ' || die "qs is not running after launch; read the log with: $log"
  local errors
  errors=$($log 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "$fail_pattern" || true)
  [[ -z $errors ]] || {
    echo "$errors" >&2
    die "the bar started but logged errors (above); $load_hint"
  }
  $log 2>&1 | grep -q 'Configuration Loaded' || die "no 'Configuration Loaded' in the log yet"
  echo "test-bar: loaded cleanly"
}

hypr_point() {
  ln -sfn "$1" "$hypr_link"
  hyprctl reload >/dev/null
  sleep 1
}

hypr_errors() {
  hyprctl configerrors 2>&1 | grep -v '^[[:space:]]*$' || true
}

hypr_restore() {
  [[ -f $hypr_orig ]] || return 0
  hypr_point "$(<"$hypr_orig")"
  rm -f "$hypr_orig" "$hypr_bar"
  echo "hypr: restored"
}

hypr_copy_ignored() {
  local dest=$1 path
  while read -r path; do
    mkdir -p "$(dirname "$dest/$path")"
    cp -a "$repo/$path" "$dest/$path"
  done < <(git -C "$repo" status --short --ignored "$hypr_rel" | awk '$1 == "!!" { sub(/\/$/, "", $2); print $2 }')
}

hypr_swap() {
  local name=$1 dir=$2
  if [[ -z $(git -C "$dir" diff --name-only origin/main...HEAD -- home/hypr) ]]; then
    if [[ -f $hypr_orig ]]; then hypr_restore; else echo "hypr: unchanged"; fi
    return 0
  fi
  local orig errors live
  orig=$(readlink "$hypr_link") || die "$hypr_link is not a symlink; refusing the hypr swap"
  hypr_copy_ignored "$dir"
  [[ -f $hypr_orig ]] && orig=$(<"$hypr_orig")
  # Worktrees have no repos/, and hyprvim and the theme symlinks resolve through it.
  live=$(cd "$(dirname "$hypr_link")" && git -C "$orig" rev-parse --show-toplevel) || die "cannot find the live checkout behind $orig"
  [[ -e $dir/repos ]] || ln -s "$live/repos" "$dir/repos"
  hypr_point "$dir/$hypr_rel"
  errors=$(hypr_errors)
  if [[ -n $errors ]]; then
    hypr_point "$orig"
    rm -f "$hypr_orig" "$hypr_bar"
    echo "$errors" >&2
    die "Hyprland reported config errors on the test bar (above); hypr link restored"
  fi
  echo "$orig" >"$hypr_orig"
  echo "$name" >"$hypr_bar"
  echo "hypr: swapped"
}

status() {
  local line path name dir branch head state=current
  line=$(pgrep -af '^qs ' || true)
  echo "qs: ${line:-not running}"
  path=$(sed -n 's/.* -p \([^ ]*\).*/\1/p' <<<"$line" | head -1)
  if [[ $path == "$bars"/* ]]; then
    name=${path#"$bars"/}
    name=${name%%/*}
    dir="$bars/$name"
    echo "bar: test bar '$name'"
    if [[ -d $dir ]]; then
      head=$(git -C "$dir" rev-parse --short HEAD)
      if [[ -f $dir.branches ]]; then
        while read -r branch; do
          git -C "$dir" merge-base --is-ancestor "$branch" HEAD 2>/dev/null || state="stale ($branch has new commits)"
        done <"$dir.branches"
      else
        state="unknown (no branch record)"
      fi
      echo "head: $head, branches $state"
    fi
  elif [[ -n $line ]]; then
    echo "bar: stowed"
  fi
  if [[ -f $hypr_orig ]]; then
    echo "hypr: swapped to test bar '$(<"$hypr_bar")' (original $(<"$hypr_orig"))"
  else
    echo "hypr: stowed ($(readlink "$hypr_link"))"
  fi
}

probe() {
  (($# > 0)) || die "usage: test-bar.sh probe \"<ipc call args>\"..."
  require_unlocked
  local pid before call
  pid=$(pgrep -nx qs) || die "qs is not running"
  before=$(qs log --pid "$pid" 2>&1 | wc -l)
  for call in "$@"; do
    read -ra args <<<"$call"
    echo "probe: ipc call ${args[*]}"
    "$ipc" call "${args[@]}" || echo "probe: call failed: $call" >&2
    sleep 0.4
  done
  sleep 1.5
  local new warns errors repeated load_fails
  new=$(qs log --pid "$pid" 2>&1 | tail -n +"$((before + 1))" | sed 's/\x1b\[[0-9;]*m//g')
  warns=$(grep -E '^ *WARN' <<<"$new" | sort | uniq -c | sort -rn || true)
  errors=$(grep -E '^ *ERROR' <<<"$new" | sort | uniq -c | sort -rn || true)
  echo "-- new WARN lines"
  echo "${warns:-none}"
  echo "-- new ERROR lines"
  echo "${errors:-none}"
  echo "-- quickshell layers"
  hyprctl layers -j | jq -r '.[].levels[][] | select(.namespace | startswith("quickshell-")) | "\(.namespace) \(.x),\(.y) \(.w)x\(.h)"'
  repeated=$(awk '$1 > 5' <<<"$warns")
  load_fails=$(grep -E "$fail_pattern" <<<"$new" | grep -vE '^ *ERROR' || true)
  if [[ -n $load_fails ]]; then
    echo "$load_fails" >&2
    die "$load_hint"
  elif [[ -n $errors ]]; then
    die "new ERROR lines in the log"
  elif [[ -n $repeated ]]; then
    die "a WARN repeated more than 5 times"
  fi
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
  printf '%s\n' "$@" >"$dir.branches"
  (cd "$dir" && just check >/dev/null) || die "just check fails on the combined build in $dir"
  echo "test-bar: built $dir from $*"
}

replace=0
args=()
for arg in "$@"; do
  if [[ $arg == --replace ]]; then replace=1; else args+=("$arg"); fi
done
set -- "${args[@]}"

case ${1:-} in
  build)
    shift
    build "$@"
    ;;
  swap)
    dir="$bars/${2:?usage: test-bar.sh swap <name>}"
    [[ -d $dir ]] || die "no test bar at $dir"
    guard_live_bar "$2" "$replace"
    require_unlocked
    hypr_swap "${2}" "$dir"
    launch "qs -n -p $dir/$qs_rel"
    verify "qs log -p $dir/$qs_rel"
    ;;
  up)
    name=${2:?usage: test-bar.sh up <name> <branch>...}
    shift 2
    guard_live_bar "$name" "$replace"
    build "$name" "$@"
    swap_args=("$name")
    ((replace)) && swap_args+=(--replace)
    "$0" swap "${swap_args[@]}"
    ;;
  restore)
    require_unlocked
    hypr_restore
    launch "qs -n"
    verify "qs log"
    ;;
  remove)
    dir="$bars/${2:?usage: test-bar.sh remove <name>}"
    pgrep -af "^qs .*-p $dir/" >/dev/null && die "that test bar is running; run test-bar.sh restore first"
    if [[ -f $hypr_bar && $(<"$hypr_bar") == "${2}" ]]; then
      require_unlocked
      hypr_restore
    fi
    git -C "$repo" worktree remove --force "$dir"
    git -C "$repo" worktree prune
    rm -f "$dir.branches"
    echo "test-bar: removed $dir"
    ;;
  status)
    status
    ;;
  probe)
    shift
    probe "$@"
    ;;
  *)
    die "usage: test-bar.sh {up <name> <branch>... [--replace]|build <name> <branch>...|swap <name> [--replace]|restore|remove <name>|status|probe <ipc call>...}"
    ;;
esac
