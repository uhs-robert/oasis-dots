#!/usr/bin/env bash
# Usage: ship-batch.sh [--skip-review-gate] [<pr>...]; merges the PRs in order, then updates main, restarts what changed and
# checks it. --skip-review-gate skips the Codex review gate for every PR, only when the owner waived Codex or named
# another reviewer; each PR's branch check still runs.
set -euo pipefail

repo=$(git -C "$(dirname "$0")" worktree list --porcelain | awk '/^worktree /{print substr($0, 10); exit}')
ipc="$HOME/.config/hypr/scripts/qs-ipc"
bars="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/test-bars"
# shellcheck source=base.sh
source "$(dirname "$0")/base.sh"

die() {
  echo "ship-batch: $*" >&2
  exit 1
}

skip_gate=()
if [[ ${1:-} == --skip-review-gate ]]; then
  skip_gate=(--skip-review-gate)
  shift
fi

[[ $(git -C "$repo" branch --show-current) == main ]] || die "the main checkout is not on main; switch it back first"

# Waiting for reviews and checking branches take minutes and touch nothing shared, so they run before the ship lock: a
# PR still waiting for its review must not hold up another session's batch. Each PR in turn waits for its Codex review
# (requesting one for a changed head) and passes its own scoped check, in its local worktree or, for a branch pushed from
# elsewhere (a cloud session), in a temporary worktree at the PR head that is removed on every exit path. The first PR
# that is not ready stops the list: the ones before it merge, in order, and it and the rest are left for a rerun.
trap remove_temp_worktree EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
ready=() not_ready=''
for pr in "$@"; do
  if ((${#skip_gate[@]})); then
    echo "ship-batch: PR $pr: review gate skipped by request"
  elif ! (cd "$repo" && "$HOME/.claude/skills/merge-prs/merge-prs.sh" --check --wait-review --request-review "$pr"); then
    not_ready="PR $pr does not pass the review gate"
    break
  fi
  branch=$(cd "$repo" && gh pr view "$pr" --json headRefName -q .headRefName) || die "cannot read PR $pr"
  worktree=$(git -C "$repo" worktree list --porcelain | awk -v ref="branch refs/heads/$branch" '/^worktree /{w = substr($0, 10)} $0 == ref {print w; exit}')
  if [[ -z $worktree ]]; then
    echo "ship-batch: no local worktree for $branch (PR $pr); checking its head in a temporary worktree"
    add_temp_worktree "$repo" "pull/$pr/head" || die "cannot fetch the head of PR $pr into a temporary worktree"
    worktree=$temp_worktree
  fi
  branch_passed=true
  (cd "$worktree" && check_branch_here) || branch_passed=false
  remove_temp_worktree
  if ! $branch_passed; then
    not_ready="the check fails on $branch (PR $pr)"
    break
  fi
  ready+=("$pr")
done
if [[ -n $not_ready ]]; then
  ((${#ready[@]})) || die "$not_ready; nothing was merged"
  echo "ship-batch: $not_ready; merging only ${ready[*]}, in order"
fi

# Only what must happen one batch at a time on the main checkout runs under the lock: the merge, the pull, and the
# restows, reloads and restarts that follow it. Commands below that can leave a daemon behind run with fd 9 closed so it
# cannot hold the lock after this run.
take_lock "$repo" "${ready[*]}" || die "gave up waiting for the ship-batch running in this repository"
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
if [[ $before != "$after" ]] && ! git -C "$repo" diff --quiet "$before" "$after" -- home/hypr; then
  hyprctl reload 9>&- >/dev/null
  errors=$(hyprctl configerrors 9>&-)
  [[ -z ${errors//[[:space:]]/} ]] || die "Hyprland config errors after reload: $errors"
fi

if [[ $before != "$after" ]] && ! git -C "$repo" diff --quiet "$before" "$after" -- home/quickshell; then
  if pgrep -af "^qs .*-p $bars/" >/dev/null; then
    echo "ship-batch: a test bar is running; restore it with the owner-test-bar skill"
  else
    # The pull just changed the bar's files, so the running bar is often mid-reload and answers nothing, or "Not ready to
    # accept queries yet.", for a few seconds. Only a settled answer says whether the lock is up.
    for _ in $(seq 15); do
      state=$(timeout 3 "$ipc" call lock state 9>&- 2>/dev/null || true)
      [[ -z $state || $state == "Not ready"* ]] || break
      sleep 1
    done
    [[ $state == unlocked ]] || die "Quickshell changed but the lock state is '${state:-unknown}'; restart the bar once unlocked"
    hyprctl version 9>&- >/dev/null 2>&1 || die "hyprctl cannot reach Hyprland (stale HYPRLAND_INSTANCE_SIGNATURE?); restart the bar by hand"
    pkill -x qs || true
    for _ in $(seq 20); do
      pgrep -x qs >/dev/null || break
      sleep 0.2
    done
    hyprctl dispatch "hl.dsp.exec_cmd('qs -n')" 9>&- >/dev/null
    sleep 6
    pgrep -x qs >/dev/null || die "qs did not come back; read 'qs log'"
    echo "ship-batch: restarted the stowed bar"
  fi
fi

# Only now: a failure or interruption anywhere above keeps the base, so a rerun repeats the reloads and restarts.
[[ $before == "$after" ]] || owe_check "$repo" "$before"
finish_base "$repo"
release_lock

# The check of main runs after the lock is released, so a long check never holds up another batch. It checks from the
# oldest base still owed (see owe_check), so a rerun after a failed or interrupted check checks again, and the step
# records make that rerun cost only the steps that did not pass.
# Whether a pass made in a branch worktree counts for main depends on repos/: a worktree has none, so
# lib/check/steps/symlinks.sh skipped the links into it. Such a pass vouches for everything but those links, so main runs only
# that step; lib/check/passed.sh is-passed accepts the pass outright only when it was made with repos/.
# Inductive: a full pass of the base plus a scoped pass over everything changed since vouches for `after`. A base main
# does not descend from or not recorded as passed, or CHECK_FULL=1, falls back to the full check.
# The skips vouch for main's commit, not its working tree, so local edits or untracked files in the main checkout rule them out.
check_from=$(owed_check "$repo")
if [[ -n $check_from ]]; then
  main_clean=false
  [[ -z $(git -C "$repo" status --porcelain) ]] && main_clean=true
  main_passed=true
  if $main_clean && [[ -z ${CHECK_FULL:-} ]] && (cd "$repo" && lib/check/passed.sh is-passed "$after"); then
    echo "ship-batch: main's tree already passed the check; not checking it again"
  elif $main_clean && [[ -z ${CHECK_FULL:-} ]] && (cd "$repo" && lib/check/passed.sh passed-somewhere "$after"); then
    echo "ship-batch: main's tree passed the check in a worktree; checking only the links into repos/"
    (cd "$repo" && sh lib/check/steps/symlinks.sh) || main_passed=false
  elif [[ -z ${CHECK_FULL:-} ]] && base_is_ancestor "$repo" "$check_from" "$after" && (cd "$repo" && lib/check/passed.sh is-passed "$check_from"); then
    (cd "$repo" && lib/check.sh --changed "$check_from") || main_passed=false
  else
    (cd "$repo" && just check) || main_passed=false
  fi
  # Another batch may merge and pull while this check runs, changing the files under it, so this run's result says
  # nothing about main. The debt stays: that batch's check starts from this one's base and covers both.
  if [[ $(git -C "$repo" rev-parse HEAD) != "$after" ]]; then
    echo "ship-batch: main moved during the check; the check from ${check_from:0:12} is still owed, and the next ship-batch run makes it"
  elif ! $main_passed; then
    die "the check fails on main after the merge; fix it before anything else"
  else
    # With uncommitted changes in the main checkout the pass was of its working tree, not `after`'s, and the helper
    # refuses to record it.
    (cd "$repo" && lib/check/passed.sh record) || true
    settle_check "$repo"
  fi
fi

echo "ship-batch: main is at $(git -C "$repo" log --oneline -1)"
(cd "$repo" && "$HOME/.claude/skills/merge-prs/status.sh") || true
[[ -z $not_ready ]] || die "$not_ready; rerun ship-batch with it and the PRs after it once that is fixed"
