#!/usr/bin/env bash
# Usage: ship-batch.sh [--skip-review-gate] [<pr>...]; merges the PRs in order, then updates main and restarts what
# changed. Each PR's branch is checked once, while its reviewers are awaited; main is not checked after the merge (run
# `just check` there on demand). --skip-review-gate skips the reviewers' states (no waiting, no review requests) for every
# PR, only when the owner waived them or named another reviewer; unresolved review threads still block, and each PR's
# branch check still runs.
set -euo pipefail

repo=$(git -C "$(dirname "$0")" worktree list --porcelain | awk '/^worktree /{print substr($0, 10); exit}')
ipc="$HOME/.config/hypr/scripts/qs-ipc"
bars="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/test-bars"
script_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=base.sh
source "$script_dir/base.sh"
# shellcheck source=live-hypr.sh
source "$(dirname "$0")/live-hypr.sh"

die() {
  echo "ship-batch: $*" >&2
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
    echo "ship-batch: HYPRLAND_INSTANCE_SIGNATURE was unset or stale; using the live instance $live" >&2
  fi
  hypr_checked=true
}

skip_gate=()
while [[ ${1:-} == --* ]]; do
  case $1 in
  --skip-review-gate) skip_gate=(--skip-review-gate) ;;
  *) die "unknown flag $1" ;;
  esac
  shift
done
# Flags are read only up front, so one after a PR number would otherwise be taken for a PR and fail late, at the gate.
for arg; do
  [[ $arg != -* ]] || die "usage: ship-batch.sh [--skip-review-gate] [<pr>...]; $arg came after a PR number, flags go first"
done

[[ $(git -C "$repo" branch --show-current) == main ]] || die "the main checkout is not on main; switch it back first"

check_pid=''
on_exit() {
  [[ -z $check_pid ]] || kill -TERM -- "-$check_pid" 2>/dev/null
  remove_temp_worktree
}
# Waiting for reviews and checking branches take minutes and touch nothing shared, so they run before the ship lock: a
# PR still waiting for its review must not hold up another session's batch. Each PR in turn is checked while its gating
# reviewers are awaited (requesting one for a changed head), in its local worktree or, for a branch pushed from
# elsewhere (a cloud session), in a temporary worktree at the PR head that is removed on every exit path. The first PR
# that is not ready stops the list: the ones before it merge, in order, and it and the rest are left for a rerun.
trap on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
ready=() ready_branches=() checked_heads=() not_ready=''
for pr in "$@"; do
  if ((${#skip_gate[@]})); then
    echo "ship-batch: PR $pr: reviewer states skipped by request; threads still checked"
    gate_flags=(--check --skip-review-gate)
  else
    gate_flags=(--check --wait-review --request-review)
  fi
  branch=$(cd "$repo" && gh pr view "$pr" --json headRefName -q .headRefName) || die "cannot read PR $pr"
  worktree=$(git -C "$repo" worktree list --porcelain | awk -v ref="branch refs/heads/$branch" '/^worktree /{w = substr($0, 10)} $0 == ref {print w; exit}')
  if [[ -z $worktree ]]; then
    echo "ship-batch: no local worktree for $branch (PR $pr); checking its head in a temporary worktree"
    add_temp_worktree "$repo" "pull/$pr/head" || die "cannot fetch the head of PR $pr into a temporary worktree"
    worktree=$temp_worktree
  fi
  # The check runs once, here, beside the reviewer wait that takes most of the time; there is no rerun after the merge.
  # Its own process group, so on_exit can end the check's steps; its output is held back so it does not interleave with the gate's.
  # Recorded before the check starts: a commit pushed during the reviewer wait must not be credited with this check.
  checked_head=$(git -C "$worktree" rev-parse HEAD)
  check_log=$(mktemp)
  # shellcheck disable=SC2016 # expanded by the inner bash
  (cd "$worktree" && exec setsid bash -c 'source "$1" && check_branch_here' _ "$script_dir/base.sh" >"$check_log" 2>&1) 9>&- &
  check_pid=$!
  gate_passed=true
  (cd "$repo" && "$HOME/.claude/skills/merge-prs/merge-prs.sh" "${gate_flags[@]}" "$pr") || gate_passed=false
  # The group exists only once setsid has run; before that the pid is the subshell, and `wait` would block for the whole check.
  $gate_passed || {
    kill -TERM -- "-$check_pid" 2>/dev/null
    kill -TERM "$check_pid" 2>/dev/null
  } || true
  branch_passed=true
  wait "$check_pid" || branch_passed=false
  check_pid=''
  cat "$check_log"
  rm -f "$check_log"
  remove_temp_worktree
  if ! $gate_passed; then
    not_ready="PR $pr does not pass the review gate"
    break
  fi
  if ! $branch_passed; then
    not_ready="the check fails on $branch (PR $pr)"
    break
  fi
  ready+=("$pr")
  ready_branches+=("$branch")
  checked_heads+=("$checked_head")
done
if [[ -n $not_ready ]]; then
  ((${#ready[@]})) || die "$not_ready; nothing was merged"
  echo "ship-batch: $not_ready; merging only ${ready[*]}, in order"
fi

# Only what must happen one batch at a time on the main checkout runs under the lock: the merge, the pull, and the
# restows, reloads and restarts that follow it. Commands below that can leave a daemon behind run with fd 9 closed so it
# cannot hold the lock after this run.
take_lock "$repo" "${ready[*]}" || die "gave up waiting for the ship-batch running in this repository"
# Each branch was checked against the main of its own time. Another batch may have merged since, and then what would land
# was never checked, so a branch that no longer contains origin/main is not merged (nor are the ones after it). The same
# goes for a PR whose head on GitHub is not the commit that was checked (merge-prs merges the PR head, not the worktree).
git -C "$repo" fetch -q origin main 9>&- || die "cannot fetch origin/main to confirm the checked branches are current"
stale=''
for i in "${!ready[@]}"; do
  pr_head=$(cd "$repo" && gh pr view "${ready[i]}" --json headRefOid -q .headRefOid 9>&-) || die "cannot read the head of PR ${ready[i]}"
  if [[ $pr_head != "${checked_heads[i]}" ]]; then
    stale="PR head differs from the checked commit (${ready_branches[i]}, PR ${ready[i]})"
  elif ! git -C "$repo" merge-base --is-ancestor origin/main "${checked_heads[i]}"; then
    stale="main moved since ${ready_branches[i]} was checked (PR ${ready[i]})"
  else
    continue
  fi
  ready=("${ready[@]:0:i}")
  break
done
if [[ -n $stale ]]; then
  ((${#ready[@]})) || die "${not_ready:+$not_ready; }$stale; nothing was merged; rerun ship-batch"
  echo "ship-batch: $stale; merging only ${ready[*]}"
  not_ready="${not_ready:+$not_ready; }$stale"
fi
before=$(select_base "$repo")
# The reviews were waited for above, so the gate here only confirms them and never waits under the lock.
((${#ready[@]} == 0)) || (cd "$repo" && "$HOME/.claude/skills/merge-prs/merge-prs.sh" "${skip_gate[@]}" "${ready[@]}") 9>&- || die "merge-prs failed; nothing after the merge ran"
git -C "$repo" pull -q --ff-only
after=$(git -C "$repo" rev-parse HEAD)
# A recorded base that main no longer descends from (rewritten history, pruned commit) vouches for nothing: treat every
# file as changed so no reload or restart is skipped.
if ! base_is_ancestor "$repo" "$before" "$after"; then
  echo "ship-batch: ${before:0:12} is not an ancestor of main; reloading everything"
  before=$(git -C "$repo" hash-object -t tree /dev/null)
fi

qs_dir=home/quickshell/.config/quickshell
greeter_paths="^($(greeter_qs_regex "$repo" "$qs_dir")|system/etc/greetd/(quickshell/|hyprland\.lua$)|system/usr/local/bin/qs-greeter$|lib/(install/greeter|common/greeter-files)\.sh$|lib/install/greeter-monitors\.lua$|justfile$)"
changed=$(git -C "$repo" diff --name-only "$before" "$after")
if grep -Eq "$greeter_paths" <<<"$changed"; then
  if sudo -n true 2>/dev/null; then
    (cd "$repo" && just greeter-sync --install) 9>&- || die "greeter-sync failed"
    echo "ship-batch: synced the greeter"
  else
    echo "ship-batch: greeter files changed; run: just greeter-sync --install"
  fi
fi
other_greetd=$(grep -E '^system/etc/greetd/' <<<"$changed" | grep -Ev "$greeter_paths" | paste -sd' ' || true)
[[ -z $other_greetd ]] || echo "ship-batch: $other_greetd changed; deploy with: just system-apply"

# Before the reloads below, which may load a script or unit the merge added.
while IFS= read -r package; do
  (cd "$repo" && just restow "$package") 9>&- || die "restowing $package failed; run: just restow $package"
  echo "ship-batch: restowed $package (files added or removed)"
done < <(packages_to_restow "$repo" "$before" "$after")
if grep -q '^home/systemd/\.config/systemd/user/' <<<"$changed"; then
  systemctl --user daemon-reload 9>&- || die "systemctl --user daemon-reload failed"
  echo "ship-batch: reloaded the user units"
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
migrate_failure='migrating failed; fix it and rerun ship-batch (a rerun resumes), or run: just migrate-quickshell-state'
migrate() {
  $run_migrations || return 0
  (cd "$repo" && just migrate-quickshell-state) 9>&- || return 1
  echo "ship-batch: ran the install migrations ($1)"
}
migrate "before the bar restart" || die "$migrate_failure"
if [[ $before != "$after" ]] && ! git -C "$repo" diff --quiet "$before" "$after" -- home/hypr; then
  use_live_hypr "reload Hyprland by hand: hyprctl reload"
  hyprctl reload 9>&- >/dev/null || die "hyprctl reload failed (exit $?); reload Hyprland by hand: hyprctl reload"
  errors=$(hyprctl configerrors 9>&-) || die "hyprctl configerrors failed; check the config by hand: hyprctl configerrors"
  [[ -z ${errors//[[:space:]]/} ]] || die "Hyprland config errors after reload: $errors"
fi

if [[ $before != "$after" ]] && ! git -C "$repo" diff --quiet "$before" "$after" -- home/quickshell; then
  if pgrep -af "^qs .*-p $bars/" >/dev/null; then
    echo "ship-batch: a test bar is running; restore it with the owner-test-bar skill"
  else
    # The pull just changed the bar's files, so the running bar is often mid-reload and answers nothing, or "Not ready to
    # accept queries yet.", or something else odd, for a few seconds. Only "unlocked" or an explicit locked answer
    # ("secure"; see Lock.state()) settles it: any other answer, "pending" while a lock engages included, is retried.
    for _ in $(seq 15); do
      state=$(timeout 3 "$ipc" call lock state 9>&- 2>/dev/null || true)
      [[ $state == unlocked || $state == secure ]] && break
      sleep 1
    done
    # The last answer is named so a false "locked" or a bar that never settled can be diagnosed afterwards.
    case $state in
    unlocked) ;;
    secure) die "Quickshell changed but the screen is locked (lock state '$state'); restart the bar once unlocked" ;;
    *) die "Quickshell changed but the lock state never settled (last answer '${state:-none}'); restart the bar once unlocked" ;;
    esac
    use_live_hypr "restart the bar by hand"
    # `qs -n` refuses to start while the old bar lives, so a bar slow to exit on SIGTERM would be relaunched into
    # nothing and leave the owner with no bar: escalate to SIGKILL before going on. Only the owner's `qs -n` bar, bare or with
    # an absolute path, or the bare `quickshell` a crash relaunch leaves, is matched (as in restart-bar.sh): -x qs would
    # also kill other users' or sessions' test bars.
    # shellcheck source=/dev/null
    source "$repo/home/hypr/.config/hypr/scripts/bar-pattern.sh"
    # shellcheck disable=SC2154 # bar_pattern comes from bar-pattern.sh
    old_bar_pid=$(pgrep -u "$UID" -f "$bar_pattern" | head -n1 || true)
    pkill -u "$UID" -f "$bar_pattern" || true
    for _ in $(seq 20); do
      pgrep -u "$UID" -f "$bar_pattern" >/dev/null || break
      sleep 0.2
    done
    if pgrep -u "$UID" -f "$bar_pattern" >/dev/null; then
      pkill -KILL -u "$UID" -f "$bar_pattern" || true
      for _ in $(seq 10); do
        pgrep -u "$UID" -f "$bar_pattern" >/dev/null || break
        sleep 0.2
      done
    fi
    # A failure here still relaunches the bar first: dying with the old one killed would leave the owner with none.
    migrate_status=0
    # The wait above can run out (a slow exit): migrations that see a bar keep the old state and nothing would retry.
    if pgrep -u "$UID" -f "$bar_pattern" >/dev/null; then
      $run_migrations && echo "ship-batch: the old bar was still running, so migration cleanup was skipped; stop the bar and run: just migrate-quickshell-state"
    else
      migrate "after stopping the bar" || migrate_status=1
    fi
    # Everything a rerun would redo is done, so a bar failure from here on (it tells the owner to restart by hand) must not
    # leave the marker for later runs to resume from. A failed migration keeps it: the rerun repeats that step.
    ((migrate_status == 0)) && finish_base "$repo"
    hyprctl dispatch "hl.dsp.exec_cmd('qs -n')" 9>&- >/dev/null || die "hyprctl could not relaunch qs; start it by hand: hyprctl dispatch \"hl.dsp.exec_cmd('qs -n')\""
    sleep 6
    new_bar_pid=$(pgrep -u "$UID" -f "$bar_pattern" | head -n1 || true)
    [[ -n $new_bar_pid && $new_bar_pid != "$old_bar_pid" ]] || die "qs did not come back; read 'qs log'"
    ((migrate_status == 0)) || die "$migrate_failure (the bar was restarted)"
    echo "ship-batch: restarted the stowed bar"
  fi
fi
# Also reached with no bar change; clearing twice is harmless.
finish_base "$repo"
release_lock

echo "ship-batch: main is at $(git -C "$repo" log --oneline -1)"
(cd "$repo" && "$HOME/.claude/skills/merge-prs/status.sh") || true
[[ -z $not_ready ]] || die "$not_ready; rerun ship-batch with it and the PRs after it once that is fixed"
