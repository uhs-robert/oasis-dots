#!/usr/bin/env bash
# Build a throwaway Quickshell test bar from branches, swap the live bar to it, and restore the stowed bar.
set -euo pipefail

# The main checkout even when run from a linked worktree, since only it holds the gitignored files a test bar copies.
repo=$(dirname "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --path-format=absolute --git-common-dir)")
qs_rel=home/quickshell/.config/quickshell
bars="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/test-bars"
ipc="$repo/home/hypr/.config/hypr/scripts/qs-ipc"
hypr_link="$HOME/.config/hypr"
hypr_rel=home/hypr/.config/hypr
hypr_orig="$bars/.hypr_orig"
hypr_bar="$bars/.hypr_bar"
voxcmd_rel=home/voxcmd
voxcmd_bin_dir="$HOME/.local/bin"
voxcmd_config_link="$HOME/.config/voxcmd"
# The private integrations dirs, which a private dotfiles repo links into per file.
voxcmd_private_dirs=(integrations.d replacements.d)
voxcmd_bar="$bars/.voxcmd_bar"

die() {
  echo "owner-test-bar: $*" >&2
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
  # pgrep exits 1 when no test bar runs, which pipefail would turn into a silent exit.
  live=$( (pgrep -af "^qs .*-p $bars/" || true) | sed -n "s|.*-p $bars/\([^/]*\)/.*|\1|p" | head -n 1)
  [[ -z $live || $live == "$name" || $replace == 1 ]] && return 0
  [[ -f $bars/$live.branches ]] || die "test bar '$live' is running and the owner may be testing it, but it has no branch record (built by hand?), so its branches cannot be included; pass --replace once the owner agrees"
  die "test bar '$live' is running and the owner may be testing it; include its branches ($(paste -sd ' ' "$bars/$live.branches")) in this bar, or pass --replace once the owner agrees"
}

# Launch through Hyprland so qs does not inherit this shell's TMUX environment.
launch() {
  # A stale HYPRLAND_INSTANCE_SIGNATURE would let pkill stop the bar and the relaunch below fail.
  hyprctl version >/dev/null 2>&1 || die "hyprctl cannot reach Hyprland (stale HYPRLAND_INSTANCE_SIGNATURE?); not stopping qs"
  pkill -x qs || true
  for _ in $(seq 20); do
    pgrep -x qs >/dev/null || break
    sleep 0.2
  done
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
  echo "owner-test-bar: loaded cleanly"
}

# Restarts the wallpaper rotator after a hypr swap or restore, only if one is running; the new one reads the re-pointed config.
restart_rotator() {
  # Anchored on the lua process, so a shell whose command line mentions the path is never killed.
  # pgrep exits 1 with no match, which pipefail and set -e would turn into a silent exit.
  local pid cmd
  pid=$( (pgrep -f '^lua .*wallpaper/init[.]lua' || true) | head -n 1)
  [[ -n $pid ]] || return 0
  # Restarted with its own arguments, such as --location from autostart, read before it exits.
  cmd=$(tr '\0' ' ' <"/proc/$pid/cmdline")
  pkill -f '^lua .*wallpaper/init[.]lua' || true
  for _ in $(seq 20); do
    pgrep -f '^lua .*wallpaper/init[.]lua' >/dev/null || break
    sleep 0.2
  done
  hyprctl dispatch "hl.dsp.exec_cmd($(jq -Rn --arg c "${cmd% }" '$c'))" >/dev/null
  echo "rotator: restarted"
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
  restart_rotator
}

hypr_copy_ignored() {
  local dest=$1 path
  while read -r path; do
    mkdir -p "$(dirname "$dest/$path")"
    cp -a "$repo/$path" "$dest/$path"
  done < <(git -C "$repo" status --short --ignored "$hypr_rel" | awk '$1 == "!!" { sub(/\/$/, "", $2); print $2 }')
}

# Without its profile, Hyprland reloads with this machine's monitors at automatic positions.
require_machine_profile() {
  local host profile
  # Named the way config/machines/init.lua names it: whitespace trimmed, cut at the first dot.
  host=${HOSTNAME:-$(</etc/hostname)}
  host=${host//[[:space:]]/}
  profile="$hypr_rel/config/machines/${host%%.*}.lua"
  if [[ -e $repo/$profile && ! -e $1/$profile ]]; then die "$1 has no $profile; refusing the hypr swap"; fi
}

hypr_swap() {
  local name=$1 dir=$2
  if [[ -z $(git -C "$dir" diff --name-only origin/main...HEAD -- home/hypr) ]]; then
    if [[ -f $hypr_orig ]]; then hypr_restore; else echo "hypr: unchanged"; fi
    return 0
  fi
  local orig errors live
  # hypr_point reloads through hyprctl; a stale HYPRLAND_INSTANCE_SIGNATURE would fail it after the link moved.
  hyprctl version >/dev/null 2>&1 || die "hyprctl cannot reach Hyprland (stale HYPRLAND_INSTANCE_SIGNATURE?); hypr link untouched"
  orig=$(readlink "$hypr_link") || die "$hypr_link is not a symlink; refusing the hypr swap"
  hypr_copy_ignored "$dir"
  require_machine_profile "$dir"
  [[ -f $hypr_orig ]] && orig=$(<"$hypr_orig")
  # Recording a test bar as the original would make restore point back at it, and remove delete what Hyprland reads.
  [[ $orig != "$bars"/* ]] || die "$hypr_link already points into test-bars ($orig); point it back at the stowed config first"
  # Worktrees have no repos/, and hyprvim and the theme symlinks resolve through it.
  live=$(cd "$(dirname "$hypr_link")" && git -C "$orig" rev-parse --show-toplevel) || die "cannot find the live checkout behind $orig"
  [[ -e $dir/repos ]] || ln -s "$live/repos" "$dir/repos"
  # Recorded before the link moves, so a failure past this point still leaves restore able to undo it.
  echo "$orig" >"$hypr_orig"
  echo "$name" >"$hypr_bar"
  hypr_point "$dir/$hypr_rel"
  errors=$(hypr_errors)
  if [[ -n $errors ]]; then
    hypr_point "$orig"
    rm -f "$hypr_orig" "$hypr_bar"
    echo "$errors" >&2
    die "Hyprland reported config errors on the test bar (above); hypr link restored"
  fi
  echo "hypr: swapped"
  restart_rotator
}

# Every voxcmd link in ~ that resolves into a test bar, from a swap or a half-done one.
voxcmd_test_links() {
  local link
  for link in "$voxcmd_bin_dir"/* "$voxcmd_config_link"; do
    [[ -L $link && $(readlink -m "$link") == "$bars"/* ]] && echo "$link"
  done
  return 0
}

# Links the owner's private integrations into the test build, the same way their private dotfiles link them into the main checkout.
voxcmd_link_private() {
  local config=$1 sub source link
  for sub in "${voxcmd_private_dirs[@]}"; do
    [[ -d $config/$sub ]] || continue
    # The main checkout's copy too, in case the live link points at a test bar that is already gone.
    for source in "$voxcmd_config_link/$sub" "$repo/$voxcmd_rel/.config/voxcmd/$sub"; do
      for link in "$source"/*; do
        [[ -L $link && -e $link && ! -e $config/$sub/${link##*/} ]] || continue
        ln -s "$(readlink -f "$link")" "$config/$sub/${link##*/}"
      done
    done
  done
}

voxcmd_swap() {
  local name=$1 dir=$2
  if [[ -z $(git -C "$dir" diff --name-only origin/main...HEAD -- "$voxcmd_rel") ]]; then
    voxcmd_restore
    return 0
  fi
  local bin=$dir/$voxcmd_rel/.local/bin config=$dir/$voxcmd_rel/.config/voxcmd file target link main_bin
  main_bin=$(readlink -m "$repo/$voxcmd_rel/.local/bin")
  [[ -L $voxcmd_config_link ]] || die "$voxcmd_config_link is not a symlink (stow unfolded it?); refusing the voxcmd swap"
  for file in "$bin"/*; do
    target=$voxcmd_bin_dir/${file##*/}
    [[ ! -e $target || -L $target ]] || die "$target is not a symlink; refusing the voxcmd swap"
  done
  voxcmd_link_private "$config"
  # Recorded before any link moves, so restore knows to restow even if this stops halfway.
  echo "$name" >"$voxcmd_bar"
  # Links left by a previous test build that this one does not have, such as a script only it added.
  voxcmd_test_links | while read -r link; do
    [[ $(readlink -m "$link") == "$dir"/* ]] || rm -f "$link"
  done
  # Main's links for scripts this build deleted or renamed, which would otherwise keep running main's copy. Restore
  # restows them.
  for link in "$voxcmd_bin_dir"/*; do
    [[ -L $link && $(readlink -m "$link") == "$main_bin"/* && ! -e $bin/${link##*/} ]] || continue
    rm -f "$link"
  done
  mkdir -p "$voxcmd_bin_dir"
  for file in "$bin"/*; do
    ln -sfn "$file" "$voxcmd_bin_dir/${file##*/}"
  done
  ln -sfn "$config" "$voxcmd_config_link"
  echo "voxcmd: test build $name"
}

# Safe to rerun after an interrupted swap or restore: the record goes only once stow has relinked main.
voxcmd_restore() {
  local links
  links=$(voxcmd_test_links)
  if [[ -n $links || -f $voxcmd_bar ]]; then
    command -v stow >/dev/null || die "stow is not installed; cannot relink voxcmd from main"
    # stow refuses to replace links it does not own, so the test links go first.
    [[ -z $links ]] || xargs -d '\n' rm -f <<<"$links"
    # -d and -t absolute: stow run from inside home/ would target the repo itself.
    stow -d "$repo/home" -t "$HOME" -R voxcmd
    rm -f "$voxcmd_bar"
  fi
  echo "voxcmd: main"
}

# The test bars voxcmd's links point into, one per line.
voxcmd_linked_bars() {
  local link target
  voxcmd_test_links | while read -r link; do
    target=$(readlink -m "$link")
    target=${target#"$bars"/}
    echo "${target%%/*}"
  done | sort -u
}

# Whether every voxcmd link a swap to this test bar makes is in place.
voxcmd_fully_linked() {
  local voxcmd=$bars/$1/$voxcmd_rel file
  [[ $(readlink -m "$voxcmd_config_link") == "$voxcmd/.config/voxcmd" ]] || return 1
  for file in "$voxcmd/.local/bin"/*; do
    [[ $(readlink -m "$voxcmd_bin_dir/${file##*/}") == "$file" ]] || return 1
  done
}

# Which voxcmd is live; also read by .claude/status.d/quickshell.sh.
voxcmd_status() {
  local names
  names=$(voxcmd_linked_bars)
  if [[ -z $names && ! -f $voxcmd_bar ]]; then
    echo "voxcmd: main"
  elif [[ -f $voxcmd_bar && $names == "$(<"$voxcmd_bar")" ]] && voxcmd_fully_linked "$names"; then
    echo "voxcmd: test build $names"
  else
    echo "voxcmd: half swapped; run: .claude/skills/owner-test-bar/owner-test-bar.sh restore"
  fi
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
  voxcmd_status
}

probe() {
  (($# > 0)) || die "usage: owner-test-bar.sh probe \"<ipc call args>\"..."
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
  (($# > 0)) || die "usage: owner-test-bar.sh build <name> <branch>..."
  local dir="$bars/$name"
  [[ -e $dir ]] && die "$dir exists; remove it first with: owner-test-bar.sh remove $name"
  git -C "$repo" fetch -q origin || true
  git -C "$repo" worktree add -q --detach "$dir" origin/main
  local branch
  for branch in "$@"; do
    git -C "$dir" merge -q --no-edit "$branch" || die "merging $branch conflicted in $dir; resolve it there or drop the branch"
  done
  copy_assets "$dir"
  printf '%s\n' "$@" >"$dir.branches"
  (cd "$dir" && just check >/dev/null) || die "just check fails on the combined build in $dir"
  echo "owner-test-bar: built $dir from $*"
}

main() {
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
    dir="$bars/${2:?usage: owner-test-bar.sh swap <name>}"
    [[ -d $dir ]] || die "no test bar at $dir"
    guard_live_bar "$2" "$replace"
    require_unlocked
    hypr_swap "${2}" "$dir"
    voxcmd_swap "$2" "$dir"
    launch "qs -n -p $dir/$qs_rel"
    verify "qs log -p $dir/$qs_rel"
    ;;
  up)
    name=${2:?usage: owner-test-bar.sh up <name> <branch>...}
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
    voxcmd_restore
    launch "qs -n"
    verify "qs log"
    ;;
  remove)
    dir="$bars/${2:?usage: owner-test-bar.sh remove <name>}"
    pgrep -af "^qs .*-p $dir/" >/dev/null && die "that test bar is running; run owner-test-bar.sh restore first"
    if [[ -f $hypr_bar && $(<"$hypr_bar") == "${2}" ]]; then
      require_unlocked
      hypr_restore
    fi
    # The links decide too: a swap stopped halfway may have moved them for this bar under another bar's record.
    if [[ -f $voxcmd_bar && $(<"$voxcmd_bar") == "$2" ]] || grep -qxF "$2" <<<"$(voxcmd_linked_bars)"; then
      voxcmd_restore
    fi
    git -C "$repo" worktree remove --force "$dir"
    git -C "$repo" worktree prune
    rm -f "$dir.branches"
    echo "owner-test-bar: removed $dir"
    ;;
  rebuild)
    name=${2:?usage: owner-test-bar.sh rebuild <name>}
    dir="$bars/$name"
    [[ -f $dir.branches ]] || die "no test bar '$name' to rebuild"
    mapfile -t branches <"$dir.branches"
    # Checked before removal: once up refuses over another live bar, this bar and its branch record are already gone.
    guard_live_bar "$name" "$replace"
    # Removing a running bar's worktree would pull its files out from under qs, so the stowed bar takes over first.
    if pgrep -af "^qs .*-p $dir/" >/dev/null; then "$0" restore; fi
    "$0" remove "$name"
    up_args=("$name" "${branches[@]}")
    ((replace)) && up_args+=(--replace)
    "$0" up "${up_args[@]}"
    ;;
  status)
    status
    ;;
  probe)
    shift
    probe "$@"
    ;;
  *)
    die "usage: owner-test-bar.sh {up <name> <branch>... [--replace]|build <name> <branch>...|swap <name> [--replace]|restore|rebuild <name>|remove <name>|status|probe <ipc call>...}"
    ;;
  esac
}

# Sourced (by status.d, or a test against a temp HOME), it only defines the functions.
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
