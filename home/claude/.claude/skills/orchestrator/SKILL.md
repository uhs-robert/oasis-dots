---

name: orchestrator
description: Orchestrate implementation work from investigation through pull request. Work from an existing GitHub issue when provided, or create an issue first when given only a repository or working from the current repository. Delegate implementation to sub-agents, independently review the result, obtain an external Codex review, resolve valid findings efficiently, and deliver a PR ready for human review.
argument-hint: "[issue-or-repo]"
arguments:

* target
  disable-model-invocation: true

---

# Orchestrator

Act as the orchestrator, not the primary implementer.

Target: `$target`

The target may be an issue URL/number, repository URL/name, or omitted.

## Workflow

1. Resolve the repository and task.
   - Use an existing issue when provided or clearly identifiable.
   - Otherwise create an issue from the user's request before implementation.
   - Avoid duplicate issues.

2. Investigate the issue and repository.
   - Read issue context, relevant code, repository instructions, tests, and analogous implementations.
   - Produce a concise implementation plan and provide to human for approval.
   - Escalate only materially ambiguous product or architectural decisions.

3. Delegate implementation using the cheapest capable model:
   - trivial → fix directly
   - small, localized, deterministic → Haiku
   - substantial, multi-file, ambiguous, architectural, or high-risk → Sonnet
   - if Haiku discovers unexpected complexity, escalate to Sonnet

4. Give the implementer the issue, plan, constraints, relevant context, and validation requirements.
   Require a report of:
   - changes made
   - validation performed
   - deviations from plan and rationale
   - remaining concerns

5. Independently review the resulting diff.
   - Verify correctness, acceptance criteria, regressions, architecture, scope, DRYness, edge cases, tests, and repository conventions.

6. Have Codex independently review the actual issue and diff for bugs, regressions, missed requirements, unnecessary complexity, and weak tests.

7. Evaluate every material review finding yourself. Classify it as valid, partially valid, invalid, or out of scope. Do not blindly apply reviewer suggestions.

8. Resolve valid findings using the same delegation policy:
   - trivial → directly
   - small → Haiku
   - substantial → Sonnet

   Re-run Codex only if remediation materially changes the implementation.

9. Final validation:
   - relevant tests/checks pass
   - diff and git status are clean
   - no unrelated changes
   - issue requirements are satisfied
   - branch/commit state is appropriate

10. Create a PR against the appropriate base branch.
    Reference and close the issue.

11. Report:
    - issue URL
    - PR URL
    - implementation summary
    - validation performed
    - noteworthy review findings and dispositions
    - remaining risks
    - whether it is ready for human review
