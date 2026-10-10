---

name: orchestrator
description: Orchestrate implementation work from investigation through pull request. Work in a git worktree. Work from an existing PR or GitHub issue when provided, or create an issue first when given only a repository or working from the current repository. Delegate implementation to sub-agents, independently review the result, obtain an external review (Codex, or Opus when Codex is unavailable), resolve valid findings efficiently, and deliver a PR ready for human review.
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

7. Get an external review of the actual issue and diff for bugs, regressions, missed requirements, unnecessary complexity, and weak tests. Codex first; an Opus subagent when Codex is unavailable.
   - From the worktree, run `~/.claude/skills/orchestrator/codex-review.sh <base> <scratch dir outside the worktree>` as one background Bash call. It handles stall detection, timeouts, and retries, and gives up at once on a usage limit.
   - Exit 0 → read the review path it prints.
   - Exit 2 → spawn a read-only `general-purpose` agent with `model: opus` as the external reviewer. Give it the worktree path, the issue, how to get the diff (`git diff <base>...HEAD`), the root cause and design, and the same review dimensions. Name the risky areas to probe (ordering and races, lifecycle and reload paths, behavior the change silently dropped). Tell it not to edit, commit, push or comment, and require findings ranked by severity, each with file:line, a concrete failure scenario, confidence (confirmed/plausible) and a suggested fix. In the final report, name which reviewer ran and quote the line Codex printed after `codex unavailable:`.

8. Evaluate every material review finding yourself. Classify it as valid, partially valid, invalid, or out of scope. Do not blindly apply reviewer suggestions.

9. Resolve valid findings using the same delegation policy:
   - trivial → directly
   - small → Haiku
   - substantial → Sonnet
   - Sonnet fails after a corrected retry, or needs subtle correctness reasoning → Opus

   Re-run the external review (Codex, or the Opus fallback) only if remediation materially changes the implementation.

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
