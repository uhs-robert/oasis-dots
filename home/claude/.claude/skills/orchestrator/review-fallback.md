# Review fallback and merge waivers

Read when codex-review.sh exits 2, Codex is at its usage limit, or a standing merge approval depends on the external review.

- Exit 2 → spawn a read-only `general-purpose` agent with `model: opus` as the external reviewer. Give it the worktree path, the issue, the diff command (`git diff <base>...HEAD`), the root cause and design, and the review dimensions; name the risky areas to probe (ordering and races, lifecycle and reload paths, behavior the change silently dropped). It must not edit, commit, push or comment, and reports findings ranked by severity, each with file:line, a concrete failure scenario, confidence (confirmed/plausible) and a suggested fix.

- Codex at its usage limit (local or GitHub) is a standing owner waiver: an Opus "approve, no revisions" counts as Codex's, including under a standing merge approval. Merge via the repo's review-gate skip (ship-batch `--skip-review-gate`), first confirming by hand the PR has no unresolved threads, since the skip bypasses that check. Say in the PR that Opus reviewed in place of Codex; use Codex again once it is back.

- A standing merge approval that requires the external review to find nothing counts the last external round plus your own review of any targeted fixes after it (step 8 of the skill). The merge-prs gate already passes `fix`/`test` commits that touch only files the last Codex review covered, so for a material fix request the re-review yourself (`@codex review` or a rerun of codex-review.sh).
