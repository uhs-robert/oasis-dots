---
name: ship-batch
description: Open and merge the PRs for a batch of reviewed, owner-tested branches, then update main, restart the bar if needed and clean up. Use once the owner has approved merging.
---

# Ship a batch

Only after the owner has tested the branches and said to merge.

1. For each branch: rebase on `origin/main` if it is behind, push, and `gh pr create` written with the global `pr-descriptions` skill, plus a note if Codex could not run.
2. Run `.claude/skills/ship-batch/ship-batch.sh <n>...` from anywhere in the repo, PRs in merge order. It merges them with the global `merge-prs` skill's script (`~/.claude/skills/merge-prs/merge-prs.sh --wait-review`, so a running Codex review is waited out: retargets and rebases stacked PRs, removes merged clean worktrees and branches), then pulls `main`, checks the real checkout (nothing new: no check; the previous main recorded as passed there: `lib/check.sh --changed <previous main>`; otherwise the full `just check`, or always with `CHECK_FULL=1`) and records the pass (worktrees have no `repos/`, so a pass recorded in one does not count), reloads Hyprland if `home/hypr` changed, restarts the stowed bar if `home/quickshell` changed and the lock is `unlocked`, and runs `just greeter-sync --install` if the merge changed greeter files and sudo needs no password (otherwise it prints the command). With no PR numbers it only does the post-merge steps. Before merging it records main's commit in `$(git rev-parse --git-common-dir)/ship-batch-base` and checks from that commit, deleting the file only once the check passes; if a run was interrupted or its check failed, rerun `ship-batch.sh` (with the PRs not yet merged, or none) and it prints `resuming from <sha>` and checks everything merged since, even when main was already pulled. A recorded commit main no longer descends from falls back to the full check. `tests/run.sh` covers the base selection.
3. `ship-batch.sh` ends by running `~/.claude/skills/merge-prs/status.sh`; run it again whenever the owner asks what is left, and report what it lists.
4. Tick the finished items in `review.md` and update its handoff if one exists.

If `just check` fails on `main`, fix it with a small follow-up PR before anything else and tell the owner.
