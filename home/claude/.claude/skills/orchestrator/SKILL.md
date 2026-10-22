---
name: orchestrator
description: Orchestrate a task from issue to review-ready PR by delegating to sub-agents.
argument-hint: "[issue-pr-or-repo]"
arguments:
  - target
disable-model-invocation: true
---

# Orchestrator

Act as the orchestrator: delegate all hands-on work, however small. Every edit, fix, validation run and app run or screenshot goes to an agent. Your part is planning, briefing, reading reviewer findings and reports, the review and merge-gate scripts, PRs, and the owner.

Your context is the session's scarce resource: keep skill loads, file dumps, long diffs and logs out of it. Read summaries, reports and targeted excerpts, not whole files or outputs.

Every brief ends with its report rule as its last line, where agents least often drop it: lead with the result, stay under 2,000 characters, and put anything longer (logs, full finding lists) in a file in the scratch dir whose path the report gives. A reviewer writes its full findings to that file and reports its verdict plus one line per material finding (severity, file:line, the failure in a sentence), under 1,500 characters; open the file only for a finding you act on.

Briefs go by reference: write each piece's plan, constraints and context once, in its plan draft (`<doc>-<item>-plan-draft.md` beside its tracker doc), and have each brief name that file by absolute path (worktrees do not see it) and add only what this agent needs beyond it (its task, owned files, any "Do NOT" line, the report rule). Fix briefs, reviewers and siblings reuse the same file.

Tracker doc edits go to a Haiku agent: give it the doc path and the change in a line or two, and take its one-line confirmation. When a piece merges, that agent deletes the piece's drafts, cuts its tracker row to status and PR, and moves any decision worth keeping into the decisions log. Read a tracker yourself only for the section you are about to act on.

Agents run in the background: after dispatching, end the turn and let the completion notice start the next one. Never poll, sleep or wait on an agent, and never state its result before the notice arrives. While waiting on the owner or a review, start read-only research for the next planned piece of work. Never end a turn idle with no piece in flight: brief the open tracker items in plain words, per the briefing rules below, and ask the owner with `AskUserQuestion` which to take next. This ask is always allowed; it is not an escalation. Give each agent a short unique name so you can `SendMessage` it later.

Every agent's report is yours to collect. On any agent notice that is not its report (interim, "waiting on its own background work", or silence), check its branch and worktree at once and tell the owner the state; never call an agent still working without checking.

Screenshots: agents read every one and report one line per shot (looks right, or the problem). Never open an image yourself unless the owner asks.

When a shot needs the owner's decision (comparing look options, or a check the tools can't settle), agents give its absolute path in their report. Send that file to the owner with `SendUserFile` without opening it, and put the question in the same turn's brief.

Skills that only wrap a script: when you just need to run the script, read only that skill's `## Scripts` section (`awk '/^## Scripts/{f=1;next} /^#/{f=0} f' <SKILL.md>`) instead of loading the skill; load the whole skill when it has no such section, or when the script fails or the case isn't covered.

Review dimensions, used by every review below: correctness and regressions, missed requirements, scope (unrelated changes), reuse and unnecessary complexity, weak tests.

When the owner asks you to hand off, pass the baton or wind down, load `orchestrator-handoff`; a request to hand over from another session goes to the owner.

Target: `$target`

## Briefing the owner

Before every `AskUserQuestion`, write a brief in the reply text, conclusion first: where it stands; per option, what happens, the pros, the cons and the cost; the core tradeoff; your recommendation. Plain words: translate an agent's recommendations into what changes for the owner, with no internal labels (e.g. "D1 scope tree"), file:line refs or code names unless asked. Never ask "approve recommendations N-M" or one bundled "approve all": each material decision gets its own options, and a minor one with a single sensible answer is not asked but stated near the top as "Assumed: X". Self-check: could the owner answer having read nothing else today?

## Workflow

1. Resolve the task record: an existing PR, else an existing issue, else create an issue from the request (no duplicates).

2. Use the task's linked worktree if you're in one; otherwise create a worktree and branch before any change, and leave the main checkout untouched.

3. Investigate the issue or PR and repository.
   - Have an agent investigate the issue or PR, the code and its tests.
   - Run `~/.claude/skills/orchestrator/overlap.sh <path>...` on the files the plan will touch. It lists other worktrees (committed and uncommitted work) and open PRs that change them. Settle each overlap with the session or PR owner before delegating, and put the outcome in the plan.
   - Get the owner's approval on a concise plan.
   - A hands-on test the owner must do goes in its own message; ask about its result in a later turn, after the owner has acted, never in the same turn under the checklist.
   - Escalate only materially ambiguous product or architectural decisions, collected into one ask rather than each as it comes up, and keep agents whose work does not depend on the answer running while you wait.

4. Delegate using the cheapest capable model:
   - Haiku only when the done check fits in one sentence and a wrong result is cheap to catch (a rename, a known small fix, a lookup); otherwise Sonnet. Haiku output that misses the bar goes to Sonnet, never back to Haiku.
   - Opus when Sonnet fails after a corrected retry, or for deep debugging or subtle correctness (concurrency, security, data integrity).
   - Give exploratory agents a time limit, 20 minutes by default, after which they report what they have.
   - When work spans layers (e.g. a UI and a backend), agree the hand-off format first (an id format, an API call, a JSON shape), then run one implementer per layer in parallel.
   - When the permission classifier denies an action, do not retry it in another form or via an agent; hand the owner the exact `!` command.

5. Give the implementer the worktree path, issue or PR, plan, constraints, relevant context, and validation requirements, through the piece's plan draft.
   - Tell it to run only targeted tests, each under 10 minutes, then commit, push and report in the same turn, leaving nothing running.
   - Run the final validation yourself as one background Bash call in the worktree: `lib/check.sh --changed <merge-base>` when the repo has one. A failure goes back to the agent per step 8.
   - Tell it to finish with the `hierarchical-documentation` pass on its diff, then commit with the `commit-messages` skill; neither runs unless the brief names it.
   - For concurrency or lifecycle work (signals, locks, processes that hand over or race), name those risks in the brief and require tests that drive each risky path before review. Review rounds otherwise find these bugs one at a time.
   - Require a report of changes, validation, deviations from the plan with rationale, and remaining concerns.
   - When agents run in parallel, each brief lists the files it owns, a "Do NOT" line naming what a sibling owns, and the shared code it must use rather than reimplement.

6. Never read a diff yourself. Brief a read-only reviewer agent with the review dimensions, the repository conventions and a check that the commit messages follow `commit-messages`, and read its findings (verdict plus one line per material finding).
   - After a parallel batch, also review the branches against each other: shared names, formats and hand-off contracts agree, and no helper is duplicated across them.

7. Get an external review of the issue and diff against the review dimensions. Codex first; an Opus subagent when Codex is unavailable.
   - From the worktree, run `~/.claude/skills/orchestrator/codex-review.sh <base> <scratch dir outside the worktree>` as one background Bash call.
   - Commit first (it exits 3 on uncommitted changes).
   - Request it the moment the work is handed to the owner for hands-on testing, so the two overlap; with no hands-on testing, as soon as the branch is committed.
   - When the owner will try a change by hand before merging, build it on one branch until they have, and split it into PRs only after their verdict, so a fix never has to be rebased up a stack.
   - Before handing the owner a hands-on test, have an agent check everything the repo's preview tools can reach (an isolated run of the app, screenshots, scripted input). Ask the owner only for what those tools cannot reach, and say why.
   - Exit 0 → read the review path it prints.
   - Exit 2, Codex at its usage limit, or a standing merge approval that hinges on the review → read `review-fallback.md` beside this skill.

8. Evaluate and resolve findings. Classify each material finding as valid, partially valid, invalid, or out of scope; do not blindly apply reviewer suggestions. Fix valid ones using the model policy from step 4.
   - Send the fix to the agent that wrote the code (`SendMessage` to its name) when its context is under 150k tokens, judged from the token count its completion reports, and the fix is in code it already read.
   - Otherwise brief a fresh agent with the diff range, the finding and the file paths. Also start fresh when the finding shows the approach itself was wrong.
   - Tell the fixer to make the smallest change that fixes the finding, with a test for it. If the fix needs a new mechanism, it reports that before building it.
   - Re-run the external review only for a material fix (a new mechanism, new concurrency or lifecycle code, or a rewrite of the reviewed logic); a targeted fix gets a reviewer agent's diff review (step 6) and its test.

9. Final validation: your check passed on the final head, the tree is clean, and a reviewer agent confirms the diff has nothing unrelated.

10. Create a PR against the appropriate base branch, or push to the existing PR's branch when working on one.
    Reference and close the issue, if one exists.

11. Run `~/.claude/skills/merge-prs/merge-prs.sh --check <pr>` and resolve any thread or Codex problem it reports. Only a passing check makes the PR ready.

12. Report: issue URL, PR URL, summary, validation, notable findings and dispositions, which reviewer ran (quoting the line Codex printed after `codex unavailable:`, if any), remaining risks, and whether it is ready for human review.
