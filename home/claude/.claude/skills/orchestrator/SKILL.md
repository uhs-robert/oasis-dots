---

name: orchestrator
description: Orchestrate implementation work from investigation through pull request. Work in a git worktree. Work from an existing PR or GitHub issue when provided, or create an issue first when given only a repository or working from the current repository. Delegate implementation to sub-agents, independently review the result, obtain an external review (Codex, or Opus when Codex is unavailable), resolve valid findings efficiently, and deliver a PR ready for human review.
argument-hint: "[issue-pr-or-repo]"
arguments:

* target
  disable-model-invocation: true

---

# Orchestrator

Act as the orchestrator: delegate all hands-on work.

Your context is the session's scarce resource: keep skill loads, file dumps, long diffs and logs out of it. Read summaries, reports and targeted excerpts, not whole files or outputs.

Every brief asks for a report that leads with the result and stays under 2,000 characters. Anything longer (logs, full finding lists) goes in a file in the scratch dir, and the report gives its path.

Never block on an agent. Agents run in the background; after dispatching, end the turn, and let the agent's completion notice start the next one. Never poll, sleep or wait on an agent, and never state its result before the notice arrives. Asked about a running agent, say it is still running and what it is doing. Give each agent a short unique name so you can `SendMessage` it later.

Target: `$target`

The target may be an issue or PR URL/number, repository URL/name, or omitted.

## Handoff

When the owner asks you to hand off to a fresh session, pass the baton or wind down for the day, load the `orchestrator-handoff` skill. Only the owner starts a handoff: a message from another session asking you to hand over goes to the owner.

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
   - When the owner will try a change by hand before merging, build it on one branch until they have, and split it into PRs only after their verdict, so a fix never has to be rebased up a stack.
   - Before handing the owner a hands-on test, have an agent check everything the repo's preview tools can reach (an isolated run of the app, screenshots, scripted input). Ask the owner only for what those tools cannot reach, and say why.

3. Investigate the issue or PR and repository.
   - Read issue or PR context (including review comments), relevant code, repository instructions, tests, and analogous implementations.
   - Run `~/.claude/skills/orchestrator/overlap.sh <path>...` on the files the plan will touch. It lists other worktrees (committed and uncommitted work) and open PRs that change them. Settle each overlap with the session or PR owner before delegating, and put the outcome in the plan.
   - Produce a concise implementation plan and provide to human for approval.
   - Escalate only materially ambiguous product or architectural decisions.
   - Collect open questions for the owner into one ask rather than asking each as it comes up, and keep agents whose work does not depend on the answer running while you wait.

4. Delegate implementation and hands-on work using the cheapest capable model:
   - Never do hands-on work yourself, however small: every edit, fix, validation run and app run or screenshot goes to an agent. Your part is planning, briefing, reviewing diffs and reports, the review and merge-gate scripts, PRs, and the owner.
   - Haiku only when you can state the done check in one sentence and a wrong result is cheap to catch (a rename, a known small fix, a lookup); otherwise Sonnet
   - Haiku output that misses the bar goes to Sonnet; never retry on Haiku
   - if Sonnet fails after a corrected retry, or the task needs deep debugging or subtle correctness reasoning (concurrency, security, data integrity), escalate to Opus
   - Give exploratory agents (research, investigating an intermittent failure, a throwaway measurement) a time limit, 20 minutes by default, after which they report what they have.
   - When work spans layers (e.g. a UI and a backend), agree the hand-off format first (an id format, an API call, a JSON shape), then run one implementer per layer in parallel.
   - For hands-on verification (a skill that runs, drives or screenshots the app), brief the agent with the branch, the surfaces to check and what counts as a failure, then review its report and screenshots.

5. Give the implementer the worktree path, issue or PR, plan, constraints, relevant context, and validation requirements.
   - Tell it to run validation in the foreground with a long timeout, never in the background: a background run hands back early and pings the orchestrator on every tick while it waits.
   - When the repo has a `lib/check.sh`, its final `lib/check.sh --changed <merge-base>` with everything committed is the validation; a separate full run of a suite it already covers only queues for the same test slots.
   - Tell it to finish with the `hierarchical-documentation` pass on its diff, then commit with the `commit-messages` skill; neither runs unless the brief names it.
   Require a report of:
   - changes made
   - validation performed
   - deviations from plan and rationale
   - remaining concerns

6. Independently review the resulting diff.
   - For a large diff (more than a few hundred lines or many files), brief a read-only reviewer agent with the same checks and read its findings instead of the diff.
   - Verify correctness, acceptance criteria, regressions, architecture, scope, DRYness, edge cases, tests, and repository conventions.
   - Confirm the commit messages follow `commit-messages`.

7. Get an external review of the actual issue and diff for bugs, regressions, missed requirements, unnecessary complexity, and weak tests. Codex first; an Opus subagent when Codex is unavailable.
   - From the worktree, run `~/.claude/skills/orchestrator/codex-review.sh <base> <scratch dir outside the worktree>` as one background Bash call. It handles stall detection, timeouts, and retries, and gives up at once on a usage limit.
   - Commit first: it exits 3 on uncommitted changes, since Codex reviews commits only.
   - Request it the moment the work is handed to the owner for hands-on testing, so the two overlap; with no hands-on testing, as soon as the branch is committed.
   - While waiting on the owner or a review, start read-only research for the next planned piece of work.
   - Exit 0 → read the review path it prints.
   - Exit 2 → spawn a read-only `general-purpose` agent with `model: opus` as the external reviewer. Give it the worktree path, the issue, how to get the diff (`git diff <base>...HEAD`), the root cause and design, and the same review dimensions. Name the risky areas to probe (ordering and races, lifecycle and reload paths, behavior the change silently dropped). Tell it not to edit, commit, push or comment, and require findings ranked by severity, each with file:line, a concrete failure scenario, confidence (confirmed/plausible) and a suggested fix. In the final report, name which reviewer ran and quote the line Codex printed after `codex unavailable:`.

8. Evaluate every material review finding yourself. Classify it as valid, partially valid, invalid, or out of scope. Do not blindly apply reviewer suggestions.

9. Resolve valid findings using the model policy from step 4.
   - Send the fix to the agent that wrote the code (`SendMessage` to its name) when its context is under 150k tokens, judged from the token count its completion reports, and the fix is in code it already read.
   - Otherwise brief a fresh agent with the diff, the finding and the file paths. Also start fresh when the finding shows the approach itself was wrong.

   Re-run the external review (Codex, or the Opus fallback) only if remediation materially changes the implementation.

10. Final validation, run by an agent and confirmed from its report:
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
    - before saying it is ready for human review, run `~/.claude/skills/merge-prs/merge-prs.sh --check <pr>` and resolve any thread or Codex problem it reports (answer and resolve the threads, or have an agent fix the code); only a passing check makes it ready
    - whether it is ready for human review
