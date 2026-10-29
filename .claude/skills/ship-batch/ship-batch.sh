#!/usr/bin/env bash
# Usage: ship-batch.sh [--skip-review-gate] [--request-review] [<pr>...]; merges the PRs in order, pulls main and runs
# post-merge.sh to apply it. With no PR numbers it only pulls and runs post-merge.sh. Each PR's branch is checked once,
# while its reviewers are awaited; main is not checked after the merge (run `just check` there on demand).
# --skip-review-gate skips the reviewers' states (no waiting, no review requests) for every PR, only when the owner waived
# them or named another reviewer; unresolved review threads still block, and each PR's branch check still runs.
# --request-review lets the review wait comment `@codex review` on a PR whose head changed past the small-fix limit since
# its review; only for a material fix, otherwise the gate reports the problem and the caller decides.
set -euo pipefail

repo=$(git -C "$(dirname "$0")" worktree list --porcelain | awk '/^worktree /{print substr($0, 10); exit}')
script_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=base.sh
source "$script_dir/base.sh"

die() {
  echo "ship-batch: $*" >&2
  exit 1
}

skip_gate=()
request_flag=()
while [[ ${1:-} == --* ]]; do
  case $1 in
  --skip-review-gate) skip_gate=(--skip-review-gate) ;;
  --request-review) request_flag=(--request-review) ;;
  *) die "unknown flag $1" ;;
  esac
  shift
done
# Flags are read only up front, so one after a PR number would otherwise be taken for a PR and fail late, at the gate.
for arg; do
  [[ $arg != -* ]] || die "usage: ship-batch.sh [--skip-review-gate] [--request-review] [<pr>...]; $arg came after a PR number, flags go first"
done

[[ $(git -C "$repo" branch --show-current) == main ]] || die "the main checkout is not on main; switch it back first"

check_pid=''
on_exit() {
  [[ -z $check_pid ]] || kill -TERM -- "-$check_pid" 2>/dev/null
  remove_temp_worktree
}
# Waiting for reviews and checking branches take minutes and touch nothing shared, so they run before the ship lock: a
# PR still waiting for its review must not hold up another session's batch. Each PR in turn is checked while its gating
# reviewers are awaited (requesting one for a changed head only under --request-review), in its local worktree or, for a branch pushed from
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
    gate_flags=(--check --wait-review "${request_flag[@]}")
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

# Only the merge and the pull run under the lock (fd 9, closed for commands that could leave a daemon behind). It is
# released before post-merge.sh, which takes it itself.
take_lock "$repo" "merging ${ready[*]:-no PRs}" || die "gave up waiting for the ship-batch running in this repository"
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
# The reviews were waited for above, so the gate here only confirms them and never waits under the lock.
((${#ready[@]} == 0)) || (cd "$repo" && "$HOME/.claude/skills/merge-prs/merge-prs.sh" "${skip_gate[@]}" "${ready[@]}") 9>&- || die "merge-prs failed; nothing after the merge ran"
git -C "$repo" pull -q --ff-only 9>&-
# The lock is released first: post-merge takes it itself, so keeping it here would deadlock. With no PR numbers this is a
# plain pull plus post-merge. The script runs from the main checkout, which now holds the merged version.
release_lock
post_merge_status=0
"$repo/.claude/skills/ship-batch/post-merge.sh" || post_merge_status=$?

echo "ship-batch: main is at $(git -C "$repo" log --oneline -1)"
(cd "$repo" && "$HOME/.claude/skills/merge-prs/status.sh") || true
((post_merge_status == 0)) || die "post-merge failed (exit $post_merge_status); main is merged, fix what it reported and run: just post-merge"
[[ -z $not_ready ]] || die "$not_ready; rerun ship-batch with it and the PRs after it once that is fixed"
