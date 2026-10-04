---
name: ship-batch
description: Open and merge the PRs for a batch of reviewed, owner-tested branches, then update main, restart the bar if needed and clean up. Use once the owner has approved merging.
---

# Ship a batch

Only after the owner has tested the branches and said to merge.

1. For each branch: rebase on `origin/main` if it is behind, push, and `gh pr create` with a short human body (what changed, why, anything a reviewer would miss, "Part of #N" or "Closes #N" on the last PR of a tracking issue, and a note if Codex could not run). No headings unless there are 3+ sections; no attribution lines.
2. `gh pr merge <n> --merge --delete-branch` for each, checking the state afterwards.
3. Run `.claude/skills/ship-batch/ship-batch.sh` from anywhere in the repo. It pulls `main`, runs `just check` in the real checkout (worktrees have no `repos/`, so this catches what they miss), reloads Hyprland if `home/hypr` changed, restarts the stowed bar if `home/quickshell` changed and the lock is `unlocked`, then removes merged worktrees and branches.
4. Tick the finished items in `review.md` and update its handoff if one exists.

If `just check` fails on `main`, fix it with a small follow-up PR before anything else and tell the owner.
