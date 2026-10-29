#!/usr/bin/env bash
# Usage: post-merge.sh (`just post-merge`); applies what changed on main since the last successful run to the live machine:
# greeter sync, restows, unit reload, crate rebuild, install migrations, Hyprland reload and the bar restart. It never
# pulls: it applies what is checked out. ship-batch calls it after its pull; after a merge on GitHub, run ship-batch.sh
# with no PR numbers (pulls, then applies) or `git pull` then this; rerun it to recover from any failed step.
# The commit applied is recorded (record_applied) only once every step succeeded, so a failed or interrupted run leaves
# the record alone and the rerun covers everything since it, steps that already ran included (all are safe to repeat).
# It lives beside ship-batch because it shares base.sh (the lock, the restow list) and live-hypr.sh with it.
set -euo pipefail

repo=$(git -C "$(dirname "$0")" worktree list --porcelain | awk '/^worktree /{print substr($0, 10); exit}')
ipc="$HOME/.config/hypr/scripts/qs-ipc"
bars="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/test-bars"
script_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=base.sh
source "$script_dir/base.sh"
# shellcheck source=live-hypr.sh
source "$script_dir/live-hypr.sh"

die() {
  echo "post-merge: $*" >&2
  exit 1
}

# Agent shells often carry a stale or missing signature, and a caller cannot prefix one without the command leaving the
# owner's allow rule, so the first hyprctl use finds the live instance itself. A valid signature in the environment is kept.
hypr_checked=false
use_live_hypr() {
  $hypr_checked && return
  # Inside a shadow its own signature answers, so the fast path is skipped: reloading it and killing the owner's qs would split.
  if in_shadow_runtime || ! timeout 3 hyprctl version 9>&- >/dev/null 2>&1; then
    local live
    live=$(find_live_hypr_signature) || die "hyprctl cannot reach Hyprland (no instance answers 'hyprctl version'); $1"
    export HYPRLAND_INSTANCE_SIGNATURE=$live XDG_RUNTIME_DIR
    XDG_RUNTIME_DIR=$(owner_runtime_dir)
    echo "post-merge: HYPRLAND_INSTANCE_SIGNATURE was unset or stale; using the live instance $live" >&2
  fi
  hypr_checked=true
}

[[ $(git -C "$repo" branch --show-current) == main ]] || die "the main checkout is not on main; switch it back first"

# Held for the whole run: a hand run waits for a ship-batch (which releases its own lock before calling this), and two
# runs never restow or restart the bar at once. Commands below that can leave a daemon behind run with fd 9 closed so it
# cannot hold the lock after this run.
take_lock "$repo" "applying main" || die "gave up waiting for the ship-batch or post-merge running in this repository"

after=$(git -C "$repo" rev-parse HEAD)
before=$(applied_commit "$repo")
empty_tree=$(git -C "$repo" hash-object -t tree /dev/null)
if [[ -z $before ]]; then
  echo "post-merge: no earlier run is recorded; applying everything once"
  before=$empty_tree
elif ! base_is_ancestor "$repo" "$before" "$after"; then
  # Rewritten history or a pruned commit vouches for nothing: treat every file as changed so no step is skipped.
  echo "post-merge: ${before:0:12} is not an ancestor of main; applying everything"
  before=$empty_tree
elif [[ $before == "$after" ]]; then
  echo "post-merge: main is already applied (${after:0:12})"
  exit 0
fi

qs_dir=home/quickshell/.config/quickshell
greeter_paths="^($(greeter_qs_regex "$repo" "$qs_dir")|system/etc/greetd/(quickshell/|hyprland\.lua$)|system/usr/local/bin/qs-greeter$|lib/(install/greeter|common/greeter-files)\.sh$|lib/install/greeter-monitors\.lua$|justfile$)"
changed=$(git -C "$repo" diff --name-only "$before" "$after")
if grep -Eq "$greeter_paths" <<<"$changed"; then
  if sudo -n true 2>/dev/null; then
    (cd "$repo" && just greeter-sync --install) 9>&- || die "greeter-sync failed"
    echo "post-merge: synced the greeter"
  else
    echo "post-merge: greeter files changed; run: just greeter-sync --install"
  fi
fi
other_greetd=$(grep -E '^system/etc/greetd/' <<<"$changed" | grep -Ev "$greeter_paths" | paste -sd' ' || true)
[[ -z $other_greetd ]] || echo "post-merge: $other_greetd changed; deploy with: just system-apply"

# Before the reloads below, which may load a script or unit the merge added.
while IFS= read -r package; do
  (cd "$repo" && just restow "$package") 9>&- || die "restowing $package failed; run: just restow $package"
  echo "post-merge: restowed $package (files added or removed)"
done < <(packages_to_restow "$repo" "$before" "$after")
if grep -q '^home/systemd/\.config/systemd/user/' <<<"$changed"; then
  systemctl --user daemon-reload 9>&- || die "systemctl --user daemon-reload failed"
  echo "post-merge: reloaded the user units"
fi
# After the restows (the rebuild reads the stowed checkout) and before any restart, a warning in the run's output rather
# than a failure: the merge has landed either way.
rebuild_crates "$repo" "$changed"
# A pull that only edits files restows nothing, so a migration the merge added or changed would never run on its own. Run
# before the restart and, when the bar is restarted, again with the old bar gone: a migration that deletes an old file
# waits for a run with no bar up (see lib/install/migrate.sh), and the relaunched bar would count as one.
migrate_paths='^(lib/install/(migrate|load)\.sh|install\.sh|justfile)$'
run_migrations=false
grep -Eq "$migrate_paths" <<<"$changed" && run_migrations=true
migrate_failure='migrating failed; fix it and rerun: just post-merge (or just migrate-quickshell-state)'
migrate() {
  $run_migrations || return 0
  (cd "$repo" && just migrate-quickshell-state) 9>&- || return 1
  echo "post-merge: ran the install migrations ($1)"
}
migrate "before the bar restart" || die "$migrate_failure"
if ! git -C "$repo" diff --quiet "$before" "$after" -- home/hypr; then
  use_live_hypr "reload Hyprland by hand: hyprctl reload"
  hyprctl reload 9>&- >/dev/null || die "hyprctl reload failed (exit $?); reload Hyprland by hand: hyprctl reload"
  errors=$(hyprctl configerrors 9>&-) || die "hyprctl configerrors failed; check the config by hand: hyprctl configerrors"
  [[ -z ${errors//[[:space:]]/} ]] || die "Hyprland config errors after reload: $errors"
fi

if ! git -C "$repo" diff --quiet "$before" "$after" -- home/quickshell; then
  if pgrep -af "^qs .*-p $bars/" >/dev/null; then
    echo "post-merge: a test bar is running; restore it with the owner-test-bar skill"
  else
    # The pull just changed the bar's files, so the running bar is often mid-reload and answers nothing, or "Not ready to
    # accept queries yet.", or something else odd, for a few seconds. Only "unlocked" or an explicit locked answer
    # ("secure"; see Lock.state()) settles it: any other answer, "pending" while a lock engages included, is retried.
    for _ in $(seq 15); do
      state=$(timeout 3 "$ipc" call lock state 9>&- 2>/dev/null || true)
      [[ $state == unlocked || $state == secure ]] && break
      sleep 1
    done
    # The last answer is named so a false "locked" or a bar that never settled can be diagnosed afterwards. Dying here,
    # before the record, is what makes the next run retry the restart.
    case $state in
    unlocked) ;;
    secure) die "Quickshell changed but the screen is locked (lock state '$state'); the bar was not restarted and main is not recorded as applied; rerun just post-merge once unlocked" ;;
    *) die "Quickshell changed but the lock state never settled (last answer '${state:-none}'); the bar was not restarted and main is not recorded as applied; rerun just post-merge once unlocked" ;;
    esac
    use_live_hypr "restart the bar by hand"
    # restart-bar.sh stops the bar (SIGKILL after its grace, failing when the bar survives that) and starts it again; its
    # processes run without the ship lock's descriptor so none can hold the lock after this run.
    restart_bar="$HOME/.config/hypr/scripts/restart-bar.sh"
    "$restart_bar" stop 9>&- || die "the old bar did not stop, so nothing was started; fix it and rerun: just post-merge"
    # A failure here still starts the bar first: dying with the old one stopped would leave the owner with none.
    migrate_status=0
    migrate "after stopping the bar" || migrate_status=1
    "$restart_bar" start 9>&- || die "the bar did not start; read 'qs log' and start it by hand: $restart_bar start"
    ((migrate_status == 0)) || die "$migrate_failure (the bar was restarted)"
    echo "post-merge: restarted the stowed bar"
  fi
fi

# Only now: a failure or interruption anywhere above keeps the record, so a rerun repeats the reloads and restarts.
record_applied "$repo" "$after"
echo "post-merge: applied ${after:0:12}"
