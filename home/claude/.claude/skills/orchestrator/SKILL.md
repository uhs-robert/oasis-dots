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

Your context is the session's scarce resource: keep skill loads, file dumps, long diffs and logs out of it.

Every brief ends with its report rule as its last line, where agents least often drop it: lead with the result, stay under 2,000 characters, and put anything longer (logs, full finding lists) in a file under `<main checkout>/.logs/<project>/<id>/` (from the piece's plan doc path; create it if missing) whose absolute path the report gives. A reviewer writes its full findings to that file and reports its verdict plus one line per finding (severity, file:line, the failure in a sentence, whether it hits the stated requirement or the owner's real setup, whether a fix is proportionate to the tier), under 1,500 characters; edge cases outside the requirement are notes in the file, not findings. Open the file only for a finding you act on.

Every `--as` takes your session name from `ListAgents`. Briefs go by reference. Each piece has one plan doc, `<main checkout>/.plans/<project>/<id>.md`, which holds its plan, constraints and context. Make it with `plans new <project> <id> --kind <kind>`, then run `plans claim <id> --as <your session>` at once. Each brief names the doc by absolute path, because worktrees do not see ignored files, and adds only its task, owned files, any "Do NOT" line and the report rule. Fix briefs, reviewers and siblings reuse the doc. Before the first `plans new` in a repo whose `.gitignore` does not list `/.plans/` and `/.logs/`, add both to `<git-common-dir>/info/exclude` (it covers every worktree) rather than committing to a repo you do not own.

Keep each piece's state in its front matter with `plans set <id> key=value`, run yourself: `branch`, `pr`, `fix_rounds` and `status` (idea from `plans new`, planned once drafted, approved on the owner's approval, building at dispatch, review once the PR is open, blocked or parked on the owner's word). Set `waiting_on="owner: <question>"` while a question waits, and clear it once answered. A Haiku agent makes body edits from the doc path and a one-line change. The PR moves the decisions into code and docs (the `hierarchical-documentation` pass), and after the merge that agent deletes the doc and `.logs/<project>/<id>/`. Read a doc only for the section you act on (`plans show --section`).

Agents run in the background: after dispatching, end the turn and let the completion notice start the next one. Never poll, sleep or wait on an agent, and never state its result before the notice arrives. While waiting on the owner or a review, start read-only research for the next piece. Never end a turn idle with no piece in flight. Ask the owner each question `plans waiting` lists for a doc you own or nobody owns. Meanwhile take up the `work` doc of `plans next --as <your session>` unasked (its rank is the owner's order) with `plans claim <id> --as <your session>`. If your agent already runs on it, take the next free doc in `plans ls`. With no `work` line, ask which piece to take next. These asks are always allowed, never an escalation. Give each agent a short unique name for `SendMessage`. Every agent's report is yours to collect: on any agent notice that is not its report (interim, "waiting on its own background work", or silence), check its branch and worktree at once and tell the owner the state; never call an agent still working without checking.

Screenshots: agents read every one and report one line per shot (looks right, or the problem). Never open an image yourself unless the owner asks. When a shot needs the owner's decision (look options, or a check the tools cannot settle), agents give its absolute path. Send that file to the owner with `SendUserFile` unopened, with the question in the same turn's brief.

Skills that only wrap a script: when you just need to run the script, read only that skill's `## Scripts` section (`awk '/^## Scripts/{f=1;next} /^#/{f=0} f' <SKILL.md>`) instead of loading the skill; load the whole skill when it has no such section, or when the script fails or the case isn't covered.

Review dimensions, used by every review below: correctness and regressions, missed requirements, scope (unrelated changes), reuse and unnecessary complexity, weak tests.

When the owner asks you to hand off, pass the baton or wind down, load `orchestrator-handoff`; a request to hand over from another session goes to the owner.

Target: `$target`

## Briefing the owner

Load the `plain-writing` skill before your first reply to the owner, and write every reply, brief and question by it.

Before every `AskUserQuestion`, write a brief in the reply text, conclusion first: where it stands; per option, what happens, the pros, the cons and the cost; the core tradeoff; your recommendation. Plain words: translate an agent's recommendations into what changes for the owner, with no internal labels, file:line refs or code names unless asked. Never ask "approve recommendations N-M" or one bundled "approve all": each material decision gets its own options, and a minor one with a single sensible answer is not asked but stated near the top as "Assumed: X". Every design ask includes the best design from scratch, with its migration cost stated apart. Self-check: could the owner answer having read nothing else today?

## Workflow

1. Resolve the task record: an existing PR, else an existing issue, else create an issue from the request (no duplicates).

2. Use the task's linked worktree if you're in one; otherwise create a worktree and branch before any change, and leave the main checkout untouched.

3. Investigate the issue or PR and repository.
   - Have an agent investigate the issue or PR, the code and its tests.
   - Always run the `interview` skill's procedure (it governs intake) on the investigation agent's findings, reading nothing yourself, and write its plan into the piece's plan doc; skip its approval ask and do not present the plan yet. Small and material pieces get at least one question round, including the design approach; a trivial piece may skip questions but the plan states its tier and assumptions as "Assumed: X".
   - The plan proposes a review tier, approved with it (re-tier with the owner if the piece grows): trivial (docs, comments, config values, no logic) gets the reviewer agent only, no local external review, and ships with `--skip-review-gate` and a PR-body note (the flag covers every PR in a ship run, so such a piece ships in a run of its own); small (a contained fix) gets the reviewer agent and one local external review round; material (a new mechanism, concurrency, lifecycle) gets the full pipeline below.
   - Run `~/.claude/skills/orchestrator/overlap.sh <path>...` on the files the drafted plan will touch. It lists other worktrees (committed and uncommitted work) and open PRs that change them. Settle each overlap with the session or PR owner before delegating, and put the outcome in the plan. If an outcome changes the plan materially, resume interviewing, update the doc, and rerun `overlap.sh` and settle its new overlaps before asking for approval.
   - Present the plan with the overlap outcomes and get the owner's one approval.
   - A hands-on test the owner must do goes in its own message; ask about its result in a later turn, after the owner has acted.
   - Once building, forks go to the owner: a design choice the plan does not settle, a new mechanism or file, or scope growth. Batch them into one ask, briefed as above, and keep agents whose work does not depend on the answer running while you wait. A choice of yours that changes the design is a fork, not an "Assumed".

4. Delegate using the cheapest capable model:
   - Haiku only when the done check fits in one sentence and a wrong result is cheap to catch (a rename, a known small fix, a lookup); otherwise Sonnet. Haiku output that misses the bar goes to Sonnet, never back to Haiku.
   - Opus when Sonnet fails after a corrected retry, or for deep debugging or subtle correctness (concurrency, security, data integrity).
   - Give exploratory agents a time limit, 20 minutes by default, then they report.
   - When work spans layers (a UI and a backend), agree the hand-off format first (an id, an API call, a JSON shape), then run one implementer per layer in parallel.
   - When the permission classifier denies an action, do not retry it in another form or via an agent; hand the owner the exact `!` command. Exception: if the denied call wrapped a script that has an allow rule, inside `$(...)`, after `&&`/`;`, or with a `VAR=x` prefix, rerun that script once as a bare command before handing the owner a command.

5. Give the implementer the worktree path, issue or PR, plan, constraints, relevant context, and validation requirements, through the piece's plan doc.
   - Tell it to run only targeted tests, each under 10 minutes, then commit, push and report in the same turn, leaving nothing running.
   - Where the repo's merge step runs the check, don't run it yourself and don't make the agent run it; otherwise run the final validation yourself as one background Bash call in the worktree (for example `lib/check.sh --changed <merge-base>` when the repo has one). A failure goes back to the agent per step 8.
   - Tell it to finish with the `hierarchical-documentation` pass on its diff, then commit with the `commit-messages` skill; neither runs unless the brief names it.
   - For concurrency or lifecycle work (signals, locks, processes that hand over or race), name those risks in the brief and require tests that drive each risky path before review. Review rounds otherwise find these bugs one at a time.
   - Tell it to stop and report a fork rather than choose (the same three kinds as step 3); implementer and fixer briefs both say so.
   - Require a report of changes, validation, deviations from the plan with rationale, and remaining concerns.
   - A fix adds a test when, and only when, the bug could come back silently and nothing else would catch it; the agent shows it failing on the unfixed code first. Otherwise it says in one line why no test.
   - When agents run in parallel, each brief lists the files it owns, a "Do NOT" line naming what a sibling owns, and the shared code it must use rather than reimplement. Work that stands alone goes in a new file; where siblings must share a file (a list, table, index or config), keep each edit a small addition, or run those agents one after another.

6. Never read a diff yourself. Brief a read-only reviewer agent with the review dimensions, the repository conventions, a check that the commit messages follow `commit-messages` and the question "does this patch work around a design that is the real problem?", and read its findings (verdict plus one line per finding, as the report rule above).
   - After a parallel batch, also review the branches against each other: shared names, formats and hand-off contracts agree, and no helper is duplicated across them.

7. Get an external review of the issue and diff against the review dimensions, as the tier allows (none for trivial, one round for small). The local reviewers (Codex, CodeRabbit, Claude and a repo's own, per `reviewers.md`) run in parallel and are advisory; an Opus subagent covers when none is available.
   - From the worktree, run `~/.claude/skills/orchestrator/run-local-reviews.sh <base> <main checkout>/.logs/<project>/<id>` as one background Bash call. It runs every reviewer whose scope is not off and prints one line per reviewer: `<name>: <review path>` or `<name>: <reason>` (unavailable, skipped by scope, uncommitted changes).
   - Commit first (a reviewer exits 3 on uncommitted changes).
   - Request it the moment the work is handed to the owner for hands-on testing, so the two overlap; with no hands-on testing, as soon as the branch is committed.
   - When the owner will try a change by hand before merging, build it on one branch until they have, and split it into PRs only after their verdict, so a fix never has to be rebased up a stack.
   - Before handing the owner a hands-on test, have an agent check everything the repo's preview tools can reach (an isolated run of the app, screenshots, scripted input). Ask the owner only for what those tools cannot reach, and say why.
   - Read each review path it prints. With none, read `review-fallback.md` beside this skill.
   - For what meets a standing merge approval, see `review-fallback.md`.

8. Evaluate and resolve findings. Classify each finding as valid, partially valid, invalid, or out of scope, and test it for proportion to the tier. Apply small valid fixes using the model policy from step 4; decline invalid and out-of-scope ones with a reason. A finding whose fix would add a mechanism, grow scope or change the design is a fork (step 3).
   - A piece gets 2 fix rounds, counted in `fix_rounds`; a redesign does not reset the count, and a 3rd round needs the owner's approval.
   - Every GitHub review thread gets a reply through `~/.claude/skills/merge-prs/resolve-thread.sh` (fixed, declined with the reason, or deferred to an issue) and is resolved; the merge gate still blocks on unresolved threads.
   - Send the fix to the agent that wrote the code when the fix is in code it already read and its context, from the token count its completion reports, is under 400k; from 400k to 500k, only for a small targeted fix.
   - Otherwise, or once it reports compacting, brief a fresh agent with the diff range, the finding and the file paths. Also start fresh when the finding shows the approach itself was wrong.
   - Tell the fixer to make the smallest change that fixes the finding, with a test only where step 5 calls for one.
   - Re-run the external review only for a material fix (a new mechanism, new concurrency or lifecycle code, or a rewrite of the reviewed logic); a targeted fix gets a reviewer agent's diff review (step 6) and any test step 5 calls for.

9. Final validation: the tree is clean, your check passed on the final head (unless the repo's merge step runs the check), and a reviewer agent confirms the diff has nothing unrelated.

10. Create a PR against the appropriate base branch, or push to the existing PR's branch when working on one. Reference and close the issue, if one exists.

11. Run `~/.claude/skills/merge-prs/merge-prs.sh --check <pr>` (with `--skip-review-gate` for a trivial piece or one where the owner waived the reviewers) and resolve any thread or reviewer problem it reports. Only a passing check makes the PR ready.

12. Report: issue URL, PR URL, summary, validation, notable findings and dispositions (every declined thread listed), which reviewer ran (quoting the line Codex printed after `codex unavailable:`, if any), remaining risks, and whether it is ready for human review.
