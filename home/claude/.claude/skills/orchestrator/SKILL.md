---

name: orchestrator
description: Orchestrate implementation work from investigation through pull request. Work in a git worktree. Work from an existing PR or GitHub issue when provided, or create an issue first when given only a repository or working from the current repository. Delegate implementation to sub-agents, independently review the result, obtain an external Codex review, resolve valid findings efficiently, and deliver a PR ready for human review.
argument-hint: "[issue-pr-or-repo]"
arguments:

* target
  disable-model-invocation: true

---

# Orchestrator

Act as the orchestrator, not the primary implementer.

Target: `$target`

The target may be an issue or PR URL/number, repository URL/name, or omitted.

## Workflow

1. Resolve the repository and task.
   - If already working on an existing PR, use that PR as the task record and do not create an issue.
   - Otherwise use an existing issue when provided or clearly identifiable.
   - Otherwise create an issue from the user's request before implementation.
   - Avoid duplicate issues.

2. Ensure all work happens in a git worktree.
   - If the current directory is already a linked worktree for this task (or the existing PR's branch), use it.
   - Otherwise create a dedicated worktree and branch before any changes, and keep the main checkout untouched.
   - Pass the worktree path to every implementer and reviewer, and confirm edits land there.

3. Investigate the issue or PR and repository.
   - Read issue or PR context (including review comments), relevant code, repository instructions, tests, and analogous implementations.
   - Produce a concise implementation plan and provide to human for approval.
   - Escalate only materially ambiguous product or architectural decisions.

4. Delegate implementation using the cheapest capable model:
   - trivial → fix directly
   - small, localized, deterministic → Haiku
   - substantial, multi-file, ambiguous, architectural, or high-risk → Sonnet
   - if Haiku discovers unexpected complexity, escalate to Sonnet
   - if Sonnet fails after a corrected retry, or the task needs deep debugging or subtle correctness reasoning (concurrency, security, data integrity), escalate to Opus

5. Give the implementer the worktree path, issue or PR, plan, constraints, relevant context, and validation requirements.
   Require a report of:
   - changes made
   - validation performed
   - deviations from plan and rationale
   - remaining concerns

6. Independently review the resulting diff.
   - Verify correctness, acceptance criteria, regressions, architecture, scope, DRYness, edge cases, tests, and repository conventions.

7. Have Codex independently review the actual issue and diff for bugs, regressions, missed requirements, unnecessary complexity, and weak tests.
   - From the worktree, run it in the background: `codex exec review --base <base> --json -o <review.md> > <events.jsonl>`, both files in a scratch directory outside the worktree.
   - Codex writes `-o` only at the end, so watch `<events.jsonl>` for progress. Treat the run as stalled if that file does not grow for 2 minutes, and as failed if it exits non-zero or leaves `<review.md>` empty.
   - Kill a stalled or failed run and retry with fresh files, at most 2 retries. Cap each run at 15 minutes.
   - If Codex still fails, continue without it and state that in the final report.

8. Evaluate every material review finding yourself. Classify it as valid, partially valid, invalid, or out of scope. Do not blindly apply reviewer suggestions.

9. Resolve valid findings using the same delegation policy:
   - trivial → directly
   - small → Haiku
   - substantial → Sonnet
   - Sonnet fails after a corrected retry, or needs subtle correctness reasoning → Opus

   Re-run Codex only if remediation materially changes the implementation.

10. Final validation:
    - relevant tests/checks pass
    - diff and git status are clean
    - no unrelated changes
    - issue or PR requirements are satisfied
    - all work is in the worktree
    - branch/commit state is appropriate

11. Create a PR against the appropriate base branch, or push to the existing PR's branch when working on one.
    Reference and close the issue, if one exists.

12. Report:
    - issue URL, if any
    - PR URL
    - implementation summary
    - validation performed
    - noteworthy review findings and dispositions
    - remaining risks
    - whether it is ready for human review
