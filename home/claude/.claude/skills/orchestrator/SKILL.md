---
name: orchestrator
description: Orchestrate a task from issue to review-ready PR by delegating to sub-agents.
argument-hint: "[issue-pr-or-repo]"
arguments:
  - target
disable-model-invocation: true
---

# Orchestrator

Act as the orchestrator: delegate all hands-on work, however small. Every edit, fix, validation run and app run or screenshot goes to an agent. Your part is planning, briefing, reviewing diffs and reports, the review and merge-gate scripts, PRs, and the owner.

Your context is the session's scarce resource: keep skill loads, file dumps, long diffs and logs out of it. Read summaries, reports and targeted excerpts, not whole files or outputs.

Every brief asks for a report that leads with the result and stays under 2,000 characters. Anything longer (logs, full finding lists) goes in a file in the scratch dir, and the report gives its path.

Agents run in the background: after dispatching, end the turn and let the completion notice start the next one. Never poll, sleep or wait on an agent, and never state its result before the notice arrives. While waiting on the owner or a review, start read-only research for the next planned piece of work. Give each agent a short unique name so you can `SendMessage` it later.

Review dimensions, used by every review below: correctness and regressions, missed requirements, scope (unrelated changes), reuse and unnecessary complexity, weak tests.

When the owner asks you to hand off, pass the baton or wind down, load `orchestrator-handoff`; a request to hand over from another session goes to the owner.

Target: `$target`

## Workflow

1. Resolve the task record: an existing PR, else an existing issue, else create an issue from the request (no duplicates).

2. Use the task's linked worktree if you're in one; otherwise create a worktree and branch before any change, and leave the main checkout untouched.

3. Investigate the issue or PR and repository.
   - Have an agent investigate the issue or PR, the code and its tests.
   - Run `~/.claude/skills/orchestrator/overlap.sh <path>...` on the files the plan will touch. It lists other worktrees (committed and uncommitted work) and open PRs that change them. Settle each overlap with the session or PR owner before delegating, and put the outcome in the plan.
   - Get the owner's approval on a concise plan.
   - Escalate only materially ambiguous product or architectural decisions, collected into one ask rather than each as it comes up, and keep agents whose work does not depend on the answer running while you wait.

4. Delegate using the cheapest capable model:
   - Haiku only when the done check fits in one sentence and a wrong result is cheap to catch (a rename, a known small fix, a lookup); otherwise Sonnet. Haiku output that misses the bar goes to Sonnet, never back to Haiku.
   - Opus when Sonnet fails after a corrected retry, or for deep debugging or subtle correctness (concurrency, security, data integrity).
   - Give exploratory agents a time limit, 20 minutes by default, after which they report what they have.
   - When work spans layers (e.g. a UI and a backend), agree the hand-off format first (an id format, an API call, a JSON shape), then run one implementer per layer in parallel.

5. Give the implementer the worktree path, issue or PR, plan, constraints, relevant context, and validation requirements.
   - Tell it to run validation in the foreground with a long timeout, never in the background: a background run hands back early and pings the orchestrator on every tick while it waits.
   - When the repo has a `lib/check.sh`, its final `lib/check.sh --changed <merge-base>` with everything committed is the validation; a separate full run of a suite it already covers only queues for the same test slots.
   - Tell it to finish with the `hierarchical-documentation` pass on its diff, then commit with the `commit-messages` skill; neither runs unless the brief names it.
   - For concurrency or lifecycle work (signals, locks, processes that hand over or race), name those risks in the brief and require tests that drive each risky path before review. Review rounds otherwise find these bugs one at a time.
   - Require a report of changes, validation, deviations from the plan with rationale, and remaining concerns.

6. Review the diff yourself against the review dimensions and repository conventions. Confirm the commit messages follow `commit-messages`. For a large diff (more than a few hundred lines or many files), brief a read-only reviewer agent with the same checks and read its findings instead of the diff.

7. Get an external review of the issue and diff against the review dimensions. Codex first; an Opus subagent when Codex is unavailable.
   - From the worktree, run `~/.claude/skills/orchestrator/codex-review.sh <base> <scratch dir outside the worktree>` as one background Bash call.
   - Commit first (it exits 3 on uncommitted changes).
   - Request it the moment the work is handed to the owner for hands-on testing, so the two overlap; with no hands-on testing, as soon as the branch is committed.
   - When the owner will try a change by hand before merging, build it on one branch until they have, and split it into PRs only after their verdict, so a fix never has to be rebased up a stack.
   - Before handing the owner a hands-on test, have an agent check everything the repo's preview tools can reach (an isolated run of the app, screenshots, scripted input). Ask the owner only for what those tools cannot reach, and say why.
   - Exit 0 → read the review path it prints.
   - Exit 2 → spawn a read-only `general-purpose` agent with `model: opus` as the external reviewer. Give it the worktree path, the issue, the diff command (`git diff <base>...HEAD`), the root cause and design, and the review dimensions; name the risky areas to probe (ordering and races, lifecycle and reload paths, behavior the change silently dropped). It must not edit, commit, push or comment, and reports findings ranked by severity, each with file:line, a concrete failure scenario, confidence (confirmed/plausible) and a suggested fix.
   - Codex at its usage limit (local or GitHub) is a standing owner waiver: an Opus "approve, no revisions" counts as Codex's, including under a standing merge approval. Merge via the repo's review-gate skip (ship-batch `--skip-review-gate`), first confirming by hand the PR has no unresolved threads, since the skip bypasses that check. Say in the PR that Opus reviewed in place of Codex; use Codex again once it is back.
   - A standing merge approval that requires the external review to find nothing counts the last external round plus your own review of any targeted fixes after it (step 8). The merge-prs gate already passes `fix`/`test` commits that touch only files the last Codex review covered, so for a material fix request the re-review yourself (`@codex review` or a rerun of codex-review.sh).

8. Evaluate and resolve findings. Classify each material finding as valid, partially valid, invalid, or out of scope; do not blindly apply reviewer suggestions. Fix valid ones using the model policy from step 4.
   - Send the fix to the agent that wrote the code (`SendMessage` to its name) when its context is under 150k tokens, judged from the token count its completion reports, and the fix is in code it already read.
   - Otherwise brief a fresh agent with the diff, the finding and the file paths. Also start fresh when the finding shows the approach itself was wrong.
   - Tell the fixer to make the smallest change that fixes the finding, with a test for it. If the fix needs a new mechanism, it reports that before building it.
   - Re-run the external review only for a material fix (a new mechanism, new concurrency or lifecycle code, or a rewrite of the reviewed logic); a targeted fix gets your own diff review and its test.

9. Final validation: an agent confirms checks pass, the tree is clean, and the diff has nothing unrelated.

10. Create a PR against the appropriate base branch, or push to the existing PR's branch when working on one.
    Reference and close the issue, if one exists.

11. Run `~/.claude/skills/merge-prs/merge-prs.sh --check <pr>` and resolve any thread or Codex problem it reports. Only a passing check makes the PR ready.

12. Report: issue URL, PR URL, summary, validation, notable findings and dispositions, which reviewer ran (quoting the line Codex printed after `codex unavailable:`, if any), remaining risks, and whether it is ready for human review.
