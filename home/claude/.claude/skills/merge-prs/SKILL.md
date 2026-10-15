---
name: merge-prs
description: Merge approved GitHub PRs in order, keep PRs stacked on them open and rebased, then remove their clean local worktrees and branches and fast-forward the main checkout. Use in any repo once the owner has approved merging, or to clean up after merging stacked PRs.
---

# Merge PRs

Only after the owner has approved the merge. Run from anywhere inside the repo, PRs in merge order:

```bash
~/.claude/skills/merge-prs/merge-prs.sh [--method rebase|squash|merge] [--keep-branch] [--skip-review-gate] [--wait-review] <pr>...
```

- Before merging anything it checks every PR, and stops naming each problem if one has an unresolved review thread or a Codex review that is still running or failed (fix it, or comment `@codex review` and wait, then rerun). A PR with no Codex summary yet counts as running when Codex has put its eyes reaction on it, and as not started while it is younger than 5 minutes (`MERGE_PRS_REVIEW_START`, seconds), so a check run right after opening never passes before Codex begins; a repo without Codex only waits out that window. `--wait-review` waits for a running or not-yet-started Codex review instead, polling every 20 s for up to 20 minutes (`MERGE_PRS_REVIEW_POLL`, `MERGE_PRS_REVIEW_WAIT`), then applies the gate as usual. A Codex review of an older commit than the head passes with a note when every later commit is a `fix` or `test` touching only files the review covered, since those answer the review; mention the note to the owner. Any other later commit, or a file the review never saw, needs its own review: the gate stops, or with `--wait-review` it comments `@codex review` and waits for a review of the head (under `--check` only with `--request-review`). Rebases do not count as changes, since each side is compared with the default branch. A repo with committed build output lists its generated path prefixes in `.claude/generated-paths` (one per line, `#` comments): a later commit touching only those paths is ignored by the gate (for same-repo PRs, since only they get the pre-merge rebuild), with a note, and generated files never count as files the review never saw. `--skip-review-gate` is for when the owner explicitly waived the review.
- `merge-prs.sh --check <pr>...` runs only that gate and exits 0 when every PR passes: use it before telling the owner a PR is ready. It changes nothing (a review request under `--request-review` aside), and cannot be combined with `--method`, `--keep-branch` or `--skip-review-gate`; it takes `--wait-review`, and with it `--request-review`, so a caller can wait for every review before it merges (ship-batch does).
- The method defaults to the first of rebase, squash, merge the repo allows; `--method` forces one.
- PRs based on a merged head are retargeted to its base before the merge, and after a rebase or squash merge they are rebased onto that base and force-pushed with a lease, along with any PRs stacked on them. Fork children are retargeted but left for a manual rebase.
- A PR that GitHub reports as conflicting only because it still carries commits of a parent already merged outside the run is rebased onto its base, dropping those commits, and force-pushed with a lease; any other conflict stops the run.
- A repo can add an executable `.claude/pre-merge`, run for each PR right before its merge (after any retarget or rebase, so a stacked PR builds on the merged base) in a temporary worktree at the PR head, with `MERGE_PRS_PR`, `MERGE_PRS_BRANCH`, `MERGE_PRS_BASE` and `MERGE_PRS_REPO_ROOT` set. A head behind its base is first rebased onto it (rebase and squash only), dropping commits that touch only generated paths since the step rebuilds them, and its children are retargeted only after the step succeeds. If it commits, the commit is pushed (no force) and that exact head is merged; a non-zero exit stops the run before that PR. Fork PRs skip it with a warning, and `--check` never runs it.
- Clean worktrees of merged branches are removed and the branches deleted, switching a clean main checkout off a merged branch to the default branch first; dirty ones, and branches with commits not in a PR head seen this run, are kept with a warning (stacks merged in one run clean up fully). Fork PRs skip local cleanup. `--keep-branch` keeps the remote branch and skips local cleanup.
- A PR in the list that is already MERGED (an interrupted earlier run merged it) counts as done: it prints `#N already merged`, still removes its clean worktree and local branch, and the run goes on with the rest. Nothing is pushed for it: open PRs stacked on it (still based on its head, or on the base but containing its old head, unless that head is already in the base) get a warning with the commands to rebase them by hand, and a branch whose PR head is not available locally is kept. A closed PR still stops the run.
- A queued merge is polled for up to `MERGE_PRS_WAIT` seconds (default 600).
- The main checkout is pulled only when it is on the default branch with no tracked changes.
- Never append cleanup (`git branch -D`, `git push origin --delete`) after the script, and never put it behind `;` or a `| tail` pipe, which hides the merge's exit code. The script does its own cleanup; a failed merge followed by a remote branch delete closes the PR for good. Run any manual cleanup as a separate command after reading the result.

It stops at the first failure with the reason. On a stacked-PR rebase conflict it prints the commands to rebase that PR by hand; do that, then rerun with the PRs not yet merged. Report each output line that needs the owner (skipped worktrees, skipped pull, stale local branches).

As the final step, and whenever the owner asks what is left, run `~/.claude/skills/merge-prs/status.sh` from anywhere in the repo: a read-only summary of your open PRs, other worktrees, unmerged local branches, untracked files and the main checkout. It also runs the repo's executable `.claude/status.d/*.sh` scripts and prints each one's output under its name.

## Restacking before a merge

When a branch low in a stack changes (a fix commit, or a rebase onto main), carry the branches above it along with:

```bash
~/.claude/skills/merge-prs/restack.sh [--check "<cmd>"] [--no-push] <bottom> <next>... <top>
```

The first branch is the one already updated. Each next branch is rebased in its own worktree (or a temporary one) onto its parent with `--onto`, so commits the parent rewrote are dropped rather than replayed; `--check` runs in that worktree before the force-push with a lease. It stops on a conflict, a committed conflict marker or a failed check, printing the files and the commands to finish by hand and restack the rest. The bottom branch itself is not pushed. Run it before pushing the bottom, or right after its update, since it reads the bottom's old tip from `origin/<bottom>` or `<bottom>@{1}`.

After changing `merge-prs.sh` or `restack.sh`, run `tests/run.sh`: it replays a stale stack, a real conflict and stack restacks against a local origin and a fake `gh`.
