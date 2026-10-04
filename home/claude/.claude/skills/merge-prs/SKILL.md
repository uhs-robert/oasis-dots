---
name: merge-prs
description: Merge approved GitHub PRs in order, keep PRs stacked on them open and rebased, then remove their clean local worktrees and branches and fast-forward the main checkout. Use in any repo once the owner has approved merging, or to clean up after merging stacked PRs.
---

# Merge PRs

Only after the owner has approved the merge. Run from anywhere inside the repo, PRs in merge order:

```bash
~/.claude/skills/merge-prs/merge-prs.sh [--method rebase|squash|merge] [--keep-branch] <pr>...
```

- The method defaults to the first of rebase, squash, merge the repo allows; `--method` forces one.
- PRs based on a merged head are retargeted to its base before the merge, and after a rebase or squash merge they are rebased onto that base and force-pushed with a lease, along with any PRs stacked on them. Fork children are retargeted but left for a manual rebase.
- Clean worktrees of merged branches are removed and the branches deleted; dirty ones, and branches with commits the PR lacks, are kept with a warning. Fork PRs skip local cleanup. `--keep-branch` keeps the remote branch and skips local cleanup.
- The main checkout is pulled only when it is on the default branch with no tracked changes.

It stops at the first failure with the reason. On a stacked-PR rebase conflict it prints the commands to rebase that PR by hand; do that, then rerun with the PRs not yet merged. Report each output line that needs the owner (skipped worktrees, skipped pull, stale local branches).
