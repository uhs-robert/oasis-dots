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
# voxcmd logs while this file exists (debug() in voxcmd). The marker is present only when a swap created the file, so
# restore never deletes a log the owner turned on themselves. The marker sits beside the log so a reboot clears both; in
# the cache it would outlive the log and make restore delete one the owner turned on afterwards.
voxcmd_debug_log="${XDG_RUNTIME_DIR:-/tmp}/voxcmd/debug.log"
voxcmd_debug_marker="${voxcmd_debug_log%/*}/.debug_log_created_by_test_bar"
# Which agent session put the live test bar up, so a second session does not swap it out from under the owner.
owner_file="$bars/.owner"

die() {
  echo "owner-test-bar: $*" >&2
  exit 1
}

caller_address() {
  [[ -z ${CLAUDE_CODE_MESSAGING_SOCKET:-} ]] || echo "uds:$CLAUDE_CODE_MESSAGING_SOCKET"
}

owner_field() {
  jq -r --arg k "$1" '.[$k] // "" | if type == "array" then join(" ") else . end' "$owner_file" 2>/dev/null
}

# A claim is live while its session's messaging socket exists; a claim without a socket cannot be reached, so it is
# treated as stale.
owner_live() {
  local address
  address=$(owner_field address)
  [[ $address == uds:* && -e ${address#uds:} ]]
}

# Same session by id when both sides have one, else by socket. Two callers with neither are the owner by hand.
owned_by_caller() {
  local session address
  session=$(owner_field session)
  address=$(owner_field address)
  if [[ -n $session && -n ${CLAUDE_CODE_SESSION_ID:-} ]]; then
    [[ $session == "$CLAUDE_CODE_SESSION_ID" ]]
  elif [[ -n $address || -n $(caller_address) ]]; then
    [[ $address == "$(caller_address)" ]]
  else
    [[ -z $session && -z ${CLAUDE_CODE_SESSION_ID:-} ]]
  fi
}

# Refuses when another live session owns the test bar; a stale claim is reported and overridden.
guard_owner() {
  local take=$1 address
  [[ -f $owner_file ]] || return 0
  owned_by_caller && return 0
  if ((take)); then
    echo "owner-test-bar: taking test bar '$(owner_field bar)' over from $(owner_field address) (--take)"
  elif owner_live; then
    die "test bar '$(owner_field bar)' ($(owner_field branches)) is owned by another session since $(owner_field since); SendMessage to $(owner_field address) to coordinate, or pass --take if the owner approved"
  else
    address=$(owner_field address)
    echo "owner-test-bar: the claim on test bar '$(owner_field bar)' by ${address:-a session with no address} since $(owner_field since) is stale (its socket is gone); proceeding"
  fi
}

# Records the caller as the owner. Only the address and session id: never the messaging token.
record_owner() {
  local name=$1
  shift
  mkdir -p "$bars"
  jq -n --arg address "$(caller_address)" --arg session "${CLAUDE_CODE_SESSION_ID:-}" --arg bar "$name" \
    --arg since "$(date -Iseconds)" '{address: $address, session: $session, bar: $bar, branches: $ARGS.positional, since: $since}' \
    --args "$@" >"$owner_file.new"
  mv "$owner_file.new" "$owner_file"
}

owner_status() {
  if [[ ! -f $owner_file ]]; then
    echo "owner: none"
    return 0
  fi
  local liveness=stale session address
  owner_live && liveness=live
  session=$(owner_field session)
  address=$(owner_field address)
  echo "owner: session ${session:-unknown} at ${address:-no address}, test bar '$(owner_field bar)' since $(owner_field since), $liveness"
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
load_hint='a QML type or file failed to load; for `X is not a type` on a folder loaded by URL, add `import qs.<folder>` to the loader file (see #531)'

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

voxcmd_debug_start() {
  if [[ -e $voxcmd_debug_log && ! -f $voxcmd_debug_marker ]]; then
    echo "voxcmd: debug log at $voxcmd_debug_log (already on, left alone on restore)"
    return 0
  fi
  mkdir -p "$(dirname "$voxcmd_debug_log")"
  touch "$voxcmd_debug_log"
  touch "$voxcmd_debug_marker"
  echo "voxcmd: debug log at $voxcmd_debug_log"
}

voxcmd_debug_stop() {
  [[ -f $voxcmd_debug_marker ]] || return 0
  rm -f "$voxcmd_debug_log" "$voxcmd_debug_marker"
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
  voxcmd_debug_start
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
  voxcmd_debug_stop
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

# Dry-runs each phrase with the live voxcmd, so a phrase is checked before the owner is told to say it.
try_phrases() {
  (($# > 0)) || die "usage: owner-test-bar.sh try <phrase>..."
  local live voxcmd phrase output result option status=0
  live=$(voxcmd_status)
  if [[ $live == "voxcmd: test build "* ]]; then
    live=${live#"voxcmd: test build "}
    voxcmd=$bars/$live/$voxcmd_rel/.local/bin/voxcmd
    echo "try: test build $live"
    # The swap links ~/.config/voxcmd to this build's copy; set explicitly so the dry run does not depend on that link.
    export VOXCMD_CONFIG_DIR=$bars/$live/$voxcmd_rel/.config/voxcmd
  elif [[ $live == *"half swapped"* ]]; then
    die "voxcmd is half swapped; run restore first"
  else
    voxcmd=$voxcmd_bin_dir/voxcmd
    echo "try: no voxcmd test bar is live, using the main install"
  fi
  for phrase in "$@"; do
    output=$("$voxcmd" --dry-run "$phrase" 2>&1) || true
    result=$(sed -n 's/^result: *//p' <<<"$output" | paste -sd ';')
    option=$(sed -n '0,/^option 1:/s/^option 1: *\(.*\) (.*/\1/p' <<<"$output")
    echo "\"$phrase\": ${result:-no result (voxcmd failed)}${option:+ -> $option}"
    [[ $result == *"no match"* || $result == *refused* || -z $result ]] && status=1
  done
  return "$status"
}

# How the test bar at $1 compares with the branches it was built from.
branches_state() {
  local dir=$1 branch
  local -a notes=()
  if [[ ! -f $dir.branches ]]; then
    echo "unknown (no branch record)"
    return 0
  fi
  while read -r branch; do
    if ! git -C "$dir" rev-parse -q --verify "$branch^{commit}" >/dev/null; then
      notes+=("branch $branch deleted")
    elif ! git -C "$dir" merge-base --is-ancestor "$branch" HEAD; then
      notes+=("stale ($branch has new commits)")
    fi
  done <"$dir.branches"
  if ((${#notes[@]})); then
    local joined
    printf -v joined ', %s' "${notes[@]}"
    echo "${joined:2}"
  else
    echo current
  fi
}

status() {
  local line path name dir head
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
      echo "head: $head, branches $(branches_state "$dir")"
    fi
  elif [[ -n $line ]]; then
    echo "bar: stowed"
  fi
  owner_status
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

# Whether a PR still needs a Codex review: its latest Codex summary does not cover the head and is not running, and no
# "@codex review" was asked for since the head commit.
# shellcheck disable=SC2016 # jq variables, not shell ones.
codex_needed_jq='(.commits | last | .committedDate) as $head_date
  | ([.comments[] | select(.body | contains("codex-pull-request-review-summary"))] | last | .body // "") as $summary
  | ($summary | capture("\\| `(?<c>[0-9a-f]{7,40})` \\|").c // "") as $reviewed
  | (($reviewed != "" and (.headRefOid | startswith($reviewed))) or ($summary | test("\\*\\*Running\\*\\*"))
     or any(.comments[]; (.body | startswith("@codex review")) and .createdAt > $head_date)) | not'

# Asks Codex to review each branch's open PR while the owner tests it, so the review is done by the time they are.
# Quiet without gh or a PR: the test bar matters more than the request.
request_codex_reviews() {
  command -v gh >/dev/null || return 0
  local branch number
  for branch in "$@"; do
    branch=${branch#origin/}
    number=$(cd "$repo" && gh pr list --head "$branch" --state open --json number --jq '.[0].number // empty' 2>/dev/null) || continue
    [[ -n $number ]] || continue
    [[ $(cd "$repo" && gh pr view "$number" --json headRefOid,commits,comments --jq "$codex_needed_jq" 2>/dev/null) == true ]] || continue
    (cd "$repo" && gh pr comment "$number" --body "@codex review" >/dev/null 2>&1) || continue
    echo "codex: requested a review of #$number ($branch)"
  done
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
  # A tree already recorded as passing needs no run; otherwise only what the branches changed.
  (cd "$dir" && { lib/check/passed.sh is-passed || lib/check.sh --changed origin/main; } >/dev/null) || die "the check fails on the combined build in $dir"
  echo "owner-test-bar: built $dir from $*"
}

main() {
  replace=0
  take=0
  args=()
  for arg in "$@"; do
    case $arg in
    --replace) replace=1 ;;
    --take) take=1 ;;
    *) args+=("$arg") ;;
    esac
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
    guard_owner "$take"
    guard_live_bar "$2" "$replace"
    mapfile -t branches < <(cat "$dir.branches" 2>/dev/null)
    record_owner "$2" "${branches[@]}"
    require_unlocked
    hypr_swap "${2}" "$dir"
    voxcmd_swap "$2" "$dir"
    launch "qs -n -p $dir/$qs_rel"
    verify "qs log -p $dir/$qs_rel"
    ;;
  up)
    name=${2:?usage: owner-test-bar.sh up <name> <branch>...}
    shift 2
    guard_owner "$take"
    guard_live_bar "$name" "$replace"
    record_owner "$name" "$@"
    build "$name" "$@"
    swap_args=("$name")
    ((replace)) && swap_args+=(--replace)
    "$0" swap "${swap_args[@]}"
    request_codex_reviews "$@"
    ;;
  restore)
    guard_owner "$take"
    require_unlocked
    hypr_restore
    voxcmd_restore
    launch "qs -n"
    verify "qs log"
    rm -f "$owner_file"
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
    if [[ -f $owner_file && $(owner_field bar) == "$2" ]]; then rm -f "$owner_file"; fi
    echo "owner-test-bar: removed $dir"
    ;;
  rebuild)
    name=${2:?usage: owner-test-bar.sh rebuild <name>}
    dir="$bars/$name"
    [[ -f $dir.branches ]] || die "no test bar '$name' to rebuild"
    mapfile -t branches <"$dir.branches"
    guard_owner "$take"
    # Recorded before the nested restore and remove clear the claim, so they see this session as the owner.
    record_owner "$name" "${branches[@]}"
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
  try)
    shift
    try_phrases "$@"
    ;;
  *)
    die "usage: owner-test-bar.sh {up <name> <branch>... [--replace] [--take]|build <name> <branch>...|swap <name> [--replace] [--take]|restore [--take]|rebuild <name> [--take]|remove <name>|status|probe <ipc call>...|try <phrase>...}"
    ;;
  esac
}

# Sourced (by status.d, or a test against a temp HOME), it only defines the functions.
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
