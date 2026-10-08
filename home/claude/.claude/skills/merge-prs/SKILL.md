---
name: merge-prs
description: Merge approved GitHub PRs in order, keep PRs stacked on them open and rebased, then remove their clean local worktrees and branches and fast-forward the main checkout. Use in any repo once the owner has approved merging, or to clean up after merging stacked PRs.
---

# Merge PRs

Only after the owner has approved the merge. Run from anywhere inside the repo, PRs in merge order:

```bash
~/.claude/skills/merge-prs/merge-prs.sh [--method rebase|squash|merge] [--keep-branch] [--skip-review-gate] <pr>...
```

- Before merging anything it checks every PR, and stops naming each problem if one has an unresolved review thread or a Codex review that is still running or failed (fix it, or comment `@codex review` and wait, then rerun). A Codex review of an older commit than the head is only noted, since rebases and follow-up commits make that routine; mention the note to the owner. `--skip-review-gate` is for when the owner explicitly waived the review.
- The method defaults to the first of rebase, squash, merge the repo allows; `--method` forces one.
- PRs based on a merged head are retargeted to its base before the merge, and after a rebase or squash merge they are rebased onto that base and force-pushed with a lease, along with any PRs stacked on them. Fork children are retargeted but left for a manual rebase.
- A PR that GitHub reports as conflicting only because it still carries commits of a parent already merged outside the run is rebased onto its base, dropping those commits, and force-pushed with a lease; any other conflict stops the run.
- Clean worktrees of merged branches are removed and the branches deleted, switching a clean main checkout off a merged branch to the default branch first; dirty ones, and branches with commits not in a PR head seen this run, are kept with a warning (stacks merged in one run clean up fully). Fork PRs skip local cleanup. `--keep-branch` keeps the remote branch and skips local cleanup.
- A queued merge is polled for up to `MERGE_PRS_WAIT` seconds (default 600).
- The main checkout is pulled only when it is on the default branch with no tracked changes.

It stops at the first failure with the reason. On a stacked-PR rebase conflict it prints the commands to rebase that PR by hand; do that, then rerun with the PRs not yet merged. Report each output line that needs the owner (skipped worktrees, skipped pull, stale local branches).

As the final step, and whenever the owner asks what is left, run `~/.claude/skills/merge-prs/status.sh` from anywhere in the repo: a read-only summary of your open PRs, other worktrees, unmerged local branches, untracked files and the main checkout. It also runs the repo's executable `.claude/status.d/*.sh` scripts and prints each one's output under its name.

After changing `merge-prs.sh`, run `tests/run.sh`: it replays a stale stack and a real conflict against a local origin and a fake `gh`.
