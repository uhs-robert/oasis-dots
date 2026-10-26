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
# Hyprland's Bind.action reads this manifest, so a test build that adds an action id fails with "unknown action id"
# unless the manifest is the build's own. The binary is not rebuilt: only the files the config reads move.
djinn_rel=home/oasis-djinn
djinn_link="$HOME/.config/oasis-djinn"
djinn_bar="$bars/.djinn_bar"
voxcmd_rel=home/voxcmd
voxcmd_bin_dir="$HOME/.local/bin"
voxcmd_config_link="$HOME/.config/voxcmd"
# The private integrations dirs, which a private dotfiles repo links into per file.
voxcmd_private_dirs=(integrations.d replacements.d)
voxcmd_bar="$bars/.voxcmd_bar"
voxtype_bin_dir="$HOME/.local/bin"
voxtype_config_link="$HOME/.config/voxtype"
voxtype_units_dir="$HOME/.config/systemd/user"
# The test bar a voxtype/systemd swap came from, written before any link moves. Beside it, the units the swap enabled,
# one per line, written before each enable, so restore disables exactly those even after a failure partway.
voxtype_bar="$bars/.voxtype_bar"
voxtype_enabled="$bars/.voxtype_enabled"
# Main's units the build deletes and the swap disabled, so restore enables them again once main's links are back.
voxtype_disabled="$bars/.voxtype_disabled"
# Main's units the build deletes that were running but not enabled, which restore starts again.
voxtype_stopped="$bars/.voxtype_stopped"
# Units that stay but whose definition the build changes (a modified unit, or one with a changed drop-in); they are
# restarted onto the new definition and again onto main's.
voxtype_restarted="$bars/.voxtype_restarted"
# What the swap watches in a branch: the paths that reach ~ (not voxtype's tests), as pathspecs.
voxtype_swap_paths=(home/voxtype/.config home/voxtype/.local home/systemd/.config)
# The Rust voxcmd that `just voxcmd-build` installs from the main checkout. rs-swap points only the voxcmd link at it.
voxcmd_rs_bin="${XDG_DATA_HOME:-$HOME/.local/share}/voxcmd-rs/bin/voxcmd"
# Links are compared resolved, so the target is too: a symlinked XDG_DATA_HOME would otherwise never match.
voxcmd_rs_target=$(readlink -m "$voxcmd_rs_bin")
# The epoch second the rs swap's timer fires at. Written before the link moves; lives in the cache, so it outlasts the
# timer across a reboot, which is how status tells a lost timer from a swap that never happened.
voxcmd_rs_marker="$bars/.voxcmd_rs"
voxcmd_rs_timer="voxcmd-rs-restore"
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

# Runs a command with set -e live inside it and leaves its status in tolerated_status, always returning 0, so a caller
# can run the next step even after a failure. Read the status, not `||`: that would switch set -e off inside the command.
tolerate() {
  set +e
  (
    set -e
    "$@"
  )
  tolerated_status=$?
  set -e
}

# The manifest goes back before Hyprland reloads, since the reload reads it; a failure of one does not skip the other.
# Always returns 0 and sets restore_failed, because calling it left of `||` or `&&` would switch set -e off inside it.
restore_hypr_and_djinn() {
  restore_failed=0
  tolerate djinn_restore
  ((tolerated_status == 0)) || restore_failed=1
  tolerate hypr_restore
  ((tolerated_status == 0)) || restore_failed=1
  if ((restore_failed)); then
    echo "owner-test-bar: restore did not finish; run: .claude/skills/owner-test-bar/owner-test-bar.sh restore" >&2
  fi
}

# Copies the gitignored files under <rel> of the main checkout into the same place in the test build at <dest>.
copy_ignored_files() {
  local dest=$1 rel=$2 path
  while read -r path; do
    mkdir -p "$(dirname "$dest/$path")"
    cp -a "$repo/$path" "$dest/$path"
  done < <(git -C "$repo" status --short --ignored "$rel" | awk '$1 == "!!" { sub(/\/$/, "", $2); print $2 }')
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
  copy_ignored_files "$dir" "$hypr_rel"
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
    # The reload reads the manifest, so main's goes back first.
    djinn_restore
    hypr_point "$orig"
    rm -f "$hypr_orig" "$hypr_bar"
    echo "$errors" >&2
    die "Hyprland reported config errors on the test bar (above); hypr link restored"
  fi
  echo "hypr: swapped"
  restart_rotator
}

# Swapped when the branches touch the manifest or hypr: a hypr-only branch may use ids the manifest gains in a branch
# it is merged with, and swapping on either keeps the config and the manifest from the same build.
djinn_swap() {
  local name=$1 dir=$2
  if [[ -z $(git -C "$dir" diff --name-only origin/main...HEAD -- "$djinn_rel" home/hypr) ]]; then
    djinn_restore
    return 0
  fi
  # Never stowed on this machine: nothing reads a manifest, so a hypr test must not be blocked on it.
  if [[ ! -e $djinn_link && ! -L $djinn_link ]]; then
    echo "oasis-djinn: not stowed here, skipped"
    return 0
  fi
  [[ -L $djinn_link ]] || die "$djinn_link is not a symlink (stow unfolded it?); refusing the oasis-djinn swap"
  [[ -d $dir/$djinn_rel/.config/oasis-djinn ]] || die "$dir has no $djinn_rel/.config/oasis-djinn; refusing the oasis-djinn swap"
  # Recorded before the link moves, so restore knows to restow even if this stops halfway.
  echo "$name" >"$djinn_bar"
  ln -sfn "$dir/$djinn_rel/.config/oasis-djinn" "$djinn_link"
  echo "oasis-djinn: test build $name"
}

djinn_linked() {
  [[ -L $djinn_link && $(readlink -m "$djinn_link") == "$bars"/* ]]
}

# Safe to rerun: the record goes only once stow has relinked main.
djinn_restore() {
  if djinn_linked || [[ -f $djinn_bar ]]; then
    command -v stow >/dev/null || die "stow is not installed; cannot relink oasis-djinn from main"
    # stow refuses to replace a link it does not own, so the test link goes first.
    if djinn_linked; then rm -f "$djinn_link"; fi
    # -d and -t absolute: stow run from inside home/ would target the repo itself.
    stow -d "$repo/home" -t "$HOME" -R oasis-djinn
    rm -f "$djinn_bar"
  elif [[ ! -e $djinn_link && ! -L $djinn_link ]]; then
    echo "oasis-djinn: not stowed here"
    return 0
  fi
  echo "oasis-djinn: main"
}

djinn_status() {
  local target name
  if djinn_linked; then
    target=$(readlink -m "$djinn_link")
    name=${target#"$bars"/}
    name=${name%%/*}
    if [[ -f $djinn_bar && $(<"$djinn_bar") == "$name" ]]; then
      echo "oasis-djinn: test build $name"
    else
      echo "oasis-djinn: half swapped; run: .claude/skills/owner-test-bar/owner-test-bar.sh restore"
    fi
  elif [[ -f $djinn_bar ]]; then
    echo "oasis-djinn: half swapped; run: .claude/skills/owner-test-bar/owner-test-bar.sh restore"
  elif [[ ! -e $djinn_link && ! -L $djinn_link ]]; then
    echo "oasis-djinn: not stowed here"
  else
    echo "oasis-djinn: main"
  fi
}

# Every voxcmd link in ~ that resolves into a test bar or the Rust build, from a swap or a half-done one. The Rust link
# is listed so restore removes it before `stow -R`, which aborts on a link it does not own.
voxcmd_test_links() {
  local link target
  for link in "$voxcmd_bin_dir"/* "$voxcmd_config_link"; do
    [[ -L $link ]] || continue
    target=$(readlink -m "$link")
    # Only the voxcmd link itself: `just voxcmd-build` leaves a permanent voxcmd-rs alias to the same binary.
    [[ $target == "$bars"/* || ($link == "$voxcmd_bin_dir/voxcmd" && $target == "$voxcmd_rs_target") ]] && echo "$link"
  done
  return 0
}

voxcmd_rs_linked() {
  [[ -L $voxcmd_bin_dir/voxcmd && $(readlink -m "$voxcmd_bin_dir/voxcmd") == "$voxcmd_rs_target" ]]
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

# A test-bar command that repoints voxcmd, or restores it, would end the Rust session or die halfway; refused before it
# changes anything.
require_no_rs_swap() {
  if [[ -f $voxcmd_rs_marker ]] || voxcmd_rs_linked; then
    die "voxcmd runs the Rust build; run restore before swapping a test bar"
  fi
}

voxcmd_swap() {
  local name=$1 dir=$2
  if [[ -z $(git -C "$dir" diff --name-only origin/main...HEAD -- "$voxcmd_rel") ]]; then
    voxcmd_restore
    return 0
  fi
  require_no_rs_swap
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

# Every voxtype or systemd-unit link in ~ that points into a test bar, from a swap or a half-done one. The target is read
# one level (not resolved) so a unit's .wants link, which resolves through the unit link, is not mistaken for one.
voxtype_test_links() {
  local link
  # Depth two reaches drop-in links (x.service.d/y.conf).
  for link in "$voxtype_bin_dir"/voxtype-* "$voxtype_config_link" "$voxtype_units_dir"/* "$voxtype_units_dir"/*/*; do
    [[ -L $link && $(readlink "$link") == "$bars"/* ]] && echo "$link"
  done
  return 0
}

# Runs `systemctl --user <args> <unit>` for each unit in <file>, then deletes the file. A unit that fails stays in the
# file and the whole call dies, so a rerun of restore retries only those.
voxtype_apply() {
  local file=$1 what=$2 unit
  local -a failed=()
  shift 2
  [[ -f $file ]] || return 0
  while read -r unit; do
    [[ -n $unit ]] || continue
    systemctl --user "$@" "$unit" || failed+=("$unit")
  done <"$file"
  if ((${#failed[@]})); then
    printf '%s\n' "${failed[@]}" >"$file"
    die "could not $what ${failed[*]}; voxtype is not fully restored, rerun restore"
  fi
  rm -f "$file"
}

# Links the test build's voxtype config, its voxtype-* scripts and the units it adds or changes into ~, restarts voxtype
# onto the new config, then enables the units the branch adds. The restart comes first: a unit that replaces something
# voxtype did itself (voxtype-duck takes over the media ducking) would otherwise run alongside it for one recording.
voxtype_changes() {
  git -C "$1" diff --name-status --no-renames --diff-filter=ADM origin/main...HEAD -- "${voxtype_swap_paths[@]}"
}

voxtype_swap() {
  local name=$1 dir=$2 changes status path unit rel link
  local -a added_units=() changed_units=() deleted_units=() deleted_links=() restart_units=()
  changes=$(voxtype_changes "$dir")
  if [[ -z $changes ]]; then
    if [[ -f $voxtype_bar ]] || [[ -n $(voxtype_test_links) ]]; then voxtype_restore; else echo "voxtype: unchanged"; fi
    return 0
  fi
  # A build already on the test links goes back to main first: its units may not exist in this one.
  if [[ -f $voxtype_bar ]] || [[ -n $(voxtype_test_links) ]]; then voxtype_restore; fi
  systemctl --user show-environment >/dev/null 2>&1 || die "the systemd user manager is unreachable; refusing the voxtype swap"
  [[ -L $voxtype_config_link ]] || die "$voxtype_config_link is not a symlink (stow unfolded it?); refusing the voxtype swap"
  while IFS=$'\t' read -r status path; do
    if [[ $status == D && $path == home/voxtype/.local/bin/* ]]; then deleted_links+=("$voxtype_bin_dir/${path##*/}"); fi
    rel=${path#home/systemd/.config/systemd/user/}
    [[ $rel != "$path" ]] || continue
    # A drop-in (x.service.d/y.conf) changes the unit it extends, whatever happened to the file.
    if [[ $rel == *.d/* ]]; then restart_units+=("${rel%%.d/*}"); fi
    if [[ $status == M && $rel != */* && $rel =~ \.(service|timer|socket|path)$ ]]; then restart_units+=("$rel"); fi
    if [[ $status == D ]]; then
      deleted_links+=("$voxtype_units_dir/$rel")
      if [[ $rel != */* && $rel =~ \.(service|timer|socket|path)$ ]]; then deleted_units+=("$rel"); fi
      continue
    fi
    changed_units+=("$rel")
    # Only top-level units are enabled; drop-ins (x.service.d/y.conf) just ride along with the unit they extend.
    if [[ $status == A && $rel != */* && $rel =~ \.(service|timer|socket|path)$ ]]; then added_units+=("$rel"); fi
  done <<<"$changes"
  for unit in "${changed_units[@]}"; do
    [[ ! -e $voxtype_units_dir/$unit || -L $voxtype_units_dir/$unit ]] || die "$voxtype_units_dir/$unit is not a symlink; refusing the voxtype swap"
  done
  for link in "$dir/home/voxtype/.local/bin"/*; do
    [[ ! -e $voxtype_bin_dir/${link##*/} || -L $voxtype_bin_dir/${link##*/} ]] || die "$voxtype_bin_dir/${link##*/} is not a symlink; refusing the voxtype swap"
  done
  copy_ignored_files "$dir" home/voxtype
  # Recorded before any link moves, so restore knows to restow even if this stops halfway.
  echo "$name" >"$voxtype_bar"
  : >"$voxtype_enabled"
  : >"$voxtype_disabled"
  : >"$voxtype_stopped"
  : >"$voxtype_restarted"
  # Main's copies of what the build deletes, so they do not keep running. A deleted unit is stopped first, while its link
  # exists; one that is running without being enabled still has to stop.
  for unit in "${deleted_units[@]}"; do
    if systemctl --user is-enabled --quiet "$unit" 2>/dev/null; then
      echo "$unit" >>"$voxtype_disabled"
      systemctl --user disable --now "$unit" || die "could not disable $unit; run restore to undo the voxtype swap"
    elif systemctl --user is-active --quiet "$unit" 2>/dev/null; then
      echo "$unit" >>"$voxtype_stopped"
      systemctl --user stop "$unit" || die "could not stop $unit; run restore to undo the voxtype swap"
    fi
  done
  for link in "${deleted_links[@]}"; do
    [[ ! -L $link ]] || rm -f "$link"
  done
  mkdir -p "$voxtype_bin_dir"
  for link in "$dir/home/voxtype/.local/bin"/*; do
    ln -sfn "$link" "$voxtype_bin_dir/${link##*/}"
  done
  ln -sfn "$dir/home/voxtype/.config/voxtype" "$voxtype_config_link"
  for unit in "${changed_units[@]}"; do
    mkdir -p "$(dirname "$voxtype_units_dir/$unit")"
    ln -sfn "$dir/home/systemd/.config/systemd/user/$unit" "$voxtype_units_dir/$unit"
  done
  # Recorded before the reload; voxtype is restarted below and a unit being added or deleted is not restarted at all.
  while read -r unit; do
    [[ -n $unit && $unit != voxtype.service ]] || continue
    [[ " ${added_units[*]} ${deleted_units[*]} " != *" $unit "* ]] && echo "$unit" >>"$voxtype_restarted"
  done < <(printf '%s\n' "${restart_units[@]}" | sort -u)
  systemctl --user daemon-reload
  systemctl --user try-restart voxtype
  # Not voxtype_apply: the record stays, since restore restarts the same units.
  while read -r unit; do
    systemctl --user try-restart "$unit" || die "could not restart $unit; run restore to undo the voxtype swap"
  done <"$voxtype_restarted"
  for unit in "${added_units[@]}"; do
    echo "$unit" >>"$voxtype_enabled"
    systemctl --user enable --now "$unit" || die "could not enable $unit; run restore to undo the voxtype swap"
  done
  echo "voxtype: test build $name${added_units[*]:+ (enabled ${added_units[*]})}"
}

# Undoes voxtype_swap in the order that keeps the volume right: stop what the swap enabled (a follower restores what it
# ducked in ExecStopPost), drop the test links, restow main, then restart voxtype onto main's config. Safe to rerun: the
# record goes last, and with nothing swapped it touches nothing.
voxtype_restore() {
  local links
  links=$(voxtype_test_links)
  [[ -n $links || -f $voxtype_bar ]] || return 0
  command -v stow >/dev/null || die "stow is not installed; cannot relink voxtype from main"
  # A unit that would not stop keeps its entry, and the links stay so the retry can still find it.
  voxtype_apply "$voxtype_enabled" "disable" disable --now
  [[ -z $links ]] || xargs -d '\n' rm -f <<<"$links"
  # -d and -t absolute: stow run from inside home/ would target the repo itself. systemd is stowed unfolded, as the installer does.
  stow -d "$repo/home" -t "$HOME" -R voxtype
  stow -d "$repo/home" -t "$HOME" --no-folding -R systemd
  systemctl --user daemon-reload
  # try-restart: a voxtype that was stopped before the test stays stopped.
  systemctl --user try-restart voxtype
  voxtype_apply "$voxtype_restarted" "restart" try-restart
  voxtype_apply "$voxtype_disabled" "re-enable" enable --now
  voxtype_apply "$voxtype_stopped" "start" start
  rm -f "$voxtype_bar"
  echo "voxtype: main"
}

# The test bars voxtype's links point into, one per line.
voxtype_linked_bars() {
  local link target
  voxtype_test_links | while read -r link; do
    target=$(readlink "$link")
    target=${target#"$bars"/}
    echo "${target%%/*}"
  done | sort -u
}

# Whether every link a swap to this test bar makes is in place, and every link it removes is gone.
voxtype_fully_linked() {
  local dir=$bars/$1 status path rel file
  [[ $(readlink "$voxtype_config_link") == "$dir/home/voxtype/.config/voxtype" ]] || return 1
  for file in "$dir/home/voxtype/.local/bin"/*; do
    [[ -e $file ]] || continue
    [[ $(readlink "$voxtype_bin_dir/${file##*/}") == "$file" ]] || return 1
  done
  while IFS=$'\t' read -r status path; do
    rel=${path#home/systemd/.config/systemd/user/}
    [[ $rel != "$path" ]] || continue
    if [[ $status == D ]]; then
      [[ ! -e $voxtype_units_dir/$rel ]] || return 1
    else
      [[ $(readlink "$voxtype_units_dir/$rel") == "$dir/home/systemd/.config/systemd/user/$rel" ]] || return 1
    fi
  done < <(voxtype_changes "$dir")
}

voxtype_status() {
  local names
  names=$(voxtype_linked_bars)
  if [[ -z $names && ! -f $voxtype_bar ]]; then
    echo "voxtype: main"
  elif [[ -f $voxtype_bar && (-z $names || $names == "$(<"$voxtype_bar")") ]] && voxtype_fully_linked "$(<"$voxtype_bar")"; then
    echo "voxtype: test build $(<"$voxtype_bar") (enabled: $(paste -sd ' ' "$voxtype_enabled" 2>/dev/null || true))"
  else
    echo "voxtype: half swapped; run: .claude/skills/owner-test-bar/owner-test-bar.sh restore"
  fi
}

# Runs the Rust voxcmd for one session. Refuses rather than renews on a second call: a silent renewal would hide that a
# session is already running on a clock. The wake word stays bash (voxcmd-wake starts the stow dir's script).
voxcmd_rs_swap() {
  local minutes=${1:-60} runtime=${XDG_RUNTIME_DIR:-/tmp}/voxcmd status self main_script var
  local -a setenv=()
  [[ $minutes =~ ^[1-9][0-9]*$ ]] || die "usage: owner-test-bar.sh rs-swap [minutes]"
  [[ -x $voxcmd_rs_bin ]] || die "$voxcmd_rs_bin is not built; run just voxcmd-build in the main checkout ($repo)"
  status=$(voxcmd_status)
  [[ $status != "voxcmd: Rust"* ]] || die "already swapped ($status); restore first"
  [[ $status == "voxcmd: main" ]] || die "voxcmd is not on main ($status); restore first"
  [[ -L $voxcmd_bin_dir/voxcmd ]] || die "$voxcmd_bin_dir/voxcmd is not a symlink; refusing the rs swap"
  # A link into a stale worktree reads as main in status, and restore would replace it with the stowed copy.
  [[ $(readlink -m "$voxcmd_bin_dir/voxcmd") == "$(readlink -m "$repo/$voxcmd_rel/.local/bin")/voxcmd" ]] ||
    die "$voxcmd_bin_dir/voxcmd does not point at the main checkout's voxcmd ($(readlink -m "$voxcmd_bin_dir/voxcmd")); fix the link with restore first"
  [[ ! -e $runtime/session.json && ! -e $runtime/pending-pick.json ]] || die "voxcmd has a session or picker open; run voxcmd stop first"
  self=$(readlink -f "${BASH_SOURCE[0]}")
  # The timer runs this path later; a worktree's copy may be gone by then.
  main_script=$(readlink -f "$repo/.claude/skills/owner-test-bar/owner-test-bar.sh")
  [[ $self == "$main_script" ]] || die "run rs-swap from the main checkout ($main_script), not $self: the restore timer calls this path"
  # The transient unit gets the user manager's environment, so every variable this script derives a path from is passed on.
  for var in XDG_CACHE_HOME XDG_DATA_HOME XDG_RUNTIME_DIR; do
    [[ -z ${!var:-} ]] || setenv+=("--setenv=$var=${!var}")
  done
  mkdir -p "$bars"
  # Recorded before the link moves, so restore and status see a half swap if this stops partway.
  echo $(($(date +%s) + minutes * 60)) >"$voxcmd_rs_marker"
  ln -sfn "$voxcmd_rs_bin" "$voxcmd_bin_dir/voxcmd"
  # A transient timer outlives this shell and the agent session, so the owner is not stranded on the Rust build.
  if ! systemd-run --user --unit="$voxcmd_rs_timer" --on-active="${minutes}m" "${setenv[@]}" "$self" rs-restore; then
    voxcmd_restore >/dev/null
    die "could not start the restore timer; swap undone"
  fi
  echo "voxcmd: Rust (restores in $minutes min); restore early with: $self restore"
  echo "voxcmd: after a reboot the timer is gone and the link stays; run restore"
}

# Ends an open Rust session and the restore timer; best effort, since restore must finish whatever state it finds.
voxcmd_rs_end_session() {
  if voxcmd_rs_linked && [[ -x $voxcmd_rs_bin ]]; then "$voxcmd_rs_bin" stop >/dev/null 2>&1 || true; fi
  if [[ -f $voxcmd_rs_marker ]]; then systemctl --user stop "$voxcmd_rs_timer.timer" >/dev/null 2>&1 || true; fi
}

# Safe to rerun after an interrupted swap or restore: the record goes only once stow has relinked main.
voxcmd_restore() {
  local links
  links=$(voxcmd_test_links)
  if [[ -n $links || -f $voxcmd_bar || -f $voxcmd_rs_marker ]]; then
    command -v stow >/dev/null || die "stow is not installed; cannot relink voxcmd from main"
    voxcmd_rs_end_session
    # stow refuses to replace links it does not own, so the test links go first.
    [[ -z $links ]] || xargs -d '\n' rm -f <<<"$links"
    # -d and -t absolute: stow run from inside home/ would target the repo itself.
    stow -d "$repo/home" -t "$HOME" -R voxcmd
    rm -f "$voxcmd_bar" "$voxcmd_rs_marker"
  fi
  voxcmd_debug_stop
  echo "voxcmd: main"
}

# The test bars voxcmd's links point into, one per line.
voxcmd_linked_bars() {
  local link target
  voxcmd_test_links | while read -r link; do
    target=$(readlink -m "$link")
    [[ $target == "$bars"/* ]] || continue
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

# Minutes until the rs swap's timer fires, rounded up; 0 or less once it is due.
voxcmd_rs_minutes_left() {
  echo $((($(<"$voxcmd_rs_marker") - $(date +%s) + 59) / 60))
}

# Which voxcmd is live; also read by .claude/status.d/quickshell.sh.
voxcmd_status() {
  local names left
  names=$(voxcmd_linked_bars)
  if [[ -f $voxcmd_rs_marker ]] || voxcmd_rs_linked; then
    if [[ ! -f $voxcmd_rs_marker ]] || ! voxcmd_rs_linked || [[ -n $names ]]; then
      echo "voxcmd: half swapped; run: .claude/skills/owner-test-bar/owner-test-bar.sh restore"
      return 0
    fi
    left=$(voxcmd_rs_minutes_left)
    if ((left <= 0)); then
      echo "voxcmd: Rust (restore overdue; run: .claude/skills/owner-test-bar/owner-test-bar.sh restore)"
    elif ! systemctl --user is-active --quiet "$voxcmd_rs_timer.timer" 2>/dev/null; then
      echo "voxcmd: Rust (restore timer lost, $left min left; run: .claude/skills/owner-test-bar/owner-test-bar.sh restore)"
    else
      echo "voxcmd: Rust (restores in $left min)"
    fi
  elif [[ -z $names && ! -f $voxcmd_bar ]]; then
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
  elif [[ $live == "voxcmd: Rust"* ]]; then
    die "voxcmd runs the Rust build, which has no --dry-run; run try before rs-swap"
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
  djinn_status
  voxcmd_status
  voxtype_status
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
  local dest=$1 path rel
  while IFS= read -r -d '' path; do
    rel=${path#"$qs_rel"/}
    [[ $path == *__pycache__* ]] && continue
    # cp -L fails on a dangling link, which would abort the whole build.
    [[ -e $repo/$path ]] || {
      echo "owner-test-bar: skipping dangling asset $path" >&2
      continue
    }
    mkdir -p "$(dirname "$dest/$rel")"
    # Per file and never over an existing one, so a partly filled ignored directory still gets what it lacks.
    cp -naL "$repo/$path" "$dest/$rel"
  done < <(git -C "$repo" ls-files -z --others --ignored --exclude-standard "$qs_rel")
}

# True when the branch already contains origin/main (so the merged tree is the branch's own tree) and that head has a
# recorded `check.sh --changed` pass against it.
branch_passed() {
  git merge-base --is-ancestor origin/main "$1" && lib/check/passed.sh passed-since origin/main "$1"
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
  copy_assets "$dir/$qs_rel"
  printf '%s\n' "$@" >"$dir.branches"
  # The merged tree is fresh, so a recorded tree pass never matches it. A lone branch that already contains origin/main
  # merges to its own tree, so its recorded pass stands in; any other merge was never checked, so it runs. CHECK_NO_LOCK: this
  # must not queue behind other sessions' voxcmd suites.
  # Kept in a log beside the build, since a bare "check fails" leaves the caller no way to tell which step broke.
  (cd "$dir" && {
    lib/check/passed.sh is-passed || { (($# == 1)) && branch_passed "$1"; } || CHECK_NO_LOCK=1 lib/check.sh --changed origin/main
  } >"$dir.check.log" 2>&1) || {
    tail -n 25 "$dir.check.log" >&2
    die "the check fails on the combined build in $dir (full output $dir.check.log)"
  }
  rm -f "$dir.check.log"
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
  copy-assets) copy_assets "${2:?usage: owner-test-bar.sh copy-assets <quickshell config dir>}" ;;
  swap)
    require_no_rs_swap
    dir="$bars/${2:?usage: owner-test-bar.sh swap <name>}"
    [[ -d $dir ]] || die "no test bar at $dir"
    guard_owner "$take"
    guard_live_bar "$2" "$replace"
    mapfile -t branches < <(cat "$dir.branches" 2>/dev/null)
    record_owner "$2" "${branches[@]}"
    require_unlocked
    djinn_swap "$2" "$dir"
    # A subshell, since die exits: the manifest must not stay on the test build when the hypr swap fails. Its status
    # is read after the subshell, not through `||`: bash turns set -e off inside anything left of `||`, so a failing
    # cp or ln partway would carry on and report a half-swapped desktop as done.
    tolerate hypr_swap "$2" "$dir"
    if ((tolerated_status != 0)); then
      # The link may have moved before the failure, so Hyprland goes back too.
      restore_hypr_and_djinn
      exit 1
    fi
    voxcmd_swap "$2" "$dir"
    voxtype_swap "$2" "$dir"
    launch "qs -n -p $dir/$qs_rel"
    verify "qs log -p $dir/$qs_rel"
    ;;
  up)
    require_no_rs_swap
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
  rs-swap)
    voxcmd_rs_swap "${2:-}"
    ;;
  rs-restore)
    # What the swap's timer runs: only voxcmd, never the bar or the test-bar claim.
    voxcmd_restore
    ;;
  restore)
    guard_owner "$take"
    require_unlocked
    restore_hypr_and_djinn
    hypr_djinn_failed=$restore_failed
    voxcmd_restore
    voxtype_restore
    launch "qs -n"
    verify "qs log"
    # Kept while Hyprland or the manifest is still on a test build, so the claim still names whom to ask.
    ((hypr_djinn_failed == 0)) || exit 1
    rm -f "$owner_file"
    ;;
  remove)
    dir="$bars/${2:?usage: owner-test-bar.sh remove <name>}"
    pgrep -af "^qs .*-p $dir/" >/dev/null && die "that test bar is running; run owner-test-bar.sh restore first"
    remove_failed=0
    if [[ -f $hypr_bar && $(<"$hypr_bar") == "${2}" ]]; then
      require_unlocked
      # The manifest goes back first, as in restore; djinn_restore alone when only the manifest is on this bar.
      restore_hypr_and_djinn
      remove_failed=$restore_failed
    elif [[ -f $djinn_bar && $(<"$djinn_bar") == "$2" ]] || { djinn_linked && [[ $(readlink -m "$djinn_link") == "$dir"/* ]]; }; then
      djinn_restore
    fi
    ((remove_failed == 0)) || die "restore did not finish; not removing $dir"
    # The links decide too: a swap stopped halfway may have moved them for this bar under another bar's record.
    if [[ -f $voxcmd_bar && $(<"$voxcmd_bar") == "$2" ]] || grep -qxF "$2" <<<"$(voxcmd_linked_bars)"; then
      voxcmd_restore
    fi
    if [[ -f $voxtype_bar && $(<"$voxtype_bar") == "$2" ]] || grep -qxF "$2" <<<"$(voxtype_linked_bars)"; then
      voxtype_restore
    fi
    git -C "$repo" worktree remove --force "$dir"
    git -C "$repo" worktree prune
    rm -f "$dir.branches" "$dir.check.log"
    if [[ -f $owner_file && $(owner_field bar) == "$2" ]]; then rm -f "$owner_file"; fi
    echo "owner-test-bar: removed $dir"
    ;;
  rebuild)
    require_no_rs_swap
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
    die "usage: owner-test-bar.sh {up <name> <branch>... [--replace] [--take]|build <name> <branch>...|copy-assets <dir>|swap <name> [--replace] [--take]|restore [--take]|rs-swap [minutes]|rebuild <name> [--take]|remove <name>|status|probe <ipc call>...|try <phrase>...}"
    ;;
  esac
}

# Sourced (by status.d, or a test against a temp HOME), it only defines the functions.
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
