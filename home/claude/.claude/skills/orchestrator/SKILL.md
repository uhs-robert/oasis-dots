---
name: orchestrator
description: Orchestrate a task from issue to review-ready PR by delegating to sub-agents. To start one more orchestrator session, run ~/.claude/skills/orchestrator-handoff/spawn-orchestrator.sh.
argument-hint: "[issue-pr-or-repo] [queue] [auto]"
arguments:
  - target
---

# Orchestrator

Act as the orchestrator: delegate all hands-on work, however small. Every edit, fix, validation run and app run or screenshot goes to an agent. Your part is planning, briefing, reading reviewer findings and reports, the review and merge-gate scripts, PRs, and the owner.

Your context is the session's scarce resource: keep skill loads, file dumps, long diffs and logs out of it. Read summaries, reports and targeted excerpts, not whole files or outputs.

Every brief ends with its report rule as its last line, where agents least often drop it: "Report per worker-rules.md: lead with the result, stay under its cap, put anything longer in a file and give its path." The caps and the file location are in `worker-rules.md`. Read a reviewer's file only for a finding you act on.

Read `~/.claude/skills/orchestrator/worker-rules.md` once per session: it defines forks and lists what every worker already gets, so briefs need not repeat it.

Every `--as` takes your session name from `ListAgents`. Briefs go by reference. Each piece has one plan doc, `<main checkout>/.plans/<project>/<id>.md`, which holds its plan, constraints and context. Make it with `plans new <project> <id> --kind <kind>`, then run `plans claim <id> --as <your session>` at once. Each brief is the task, its owned files, any "Do NOT" line, the absolute paths of `~/.claude/skills/orchestrator/worker-rules.md`, the repo's `AGENTS.md` and the plan doc, and the report rule as its last line. The worker duties live in `worker-rules.md`, so the brief does not repeat them. Fix briefs, reviewers and siblings reuse the doc. Before the first `plans new` in a repo whose `.gitignore` does not list `/.plans/` and `/.logs/`, add both to `<git-common-dir>/info/exclude` (it covers every worktree) rather than committing to a repo you do not own.

Keep each piece's state in its front matter with `plans set <id> key=value`, run yourself: `branch`, `pr`, `fix_rounds` and `status` (idea from `plans new`, planned once drafted, approved on the owner's approval, building at dispatch, review once the PR is open, blocked or parked on the owner's word). Set `waiting_on="owner: <question>"` while a question waits, and clear it once answered. Make body edits yourself with `plans note <id> --section <name> "text"`, which appends a bullet (a Decisions bullet gets a date prefix, an Open questions bullet becomes a `- [ ]` item). A Haiku agent makes only large rewrites, such as the Plan section after an interview, from the doc path and a one-line change. When the owner states a context budget in chat, run `mkdir -p "${XDG_RUNTIME_DIR:-/tmp}/claude-context-budget" && echo <tokens> > "${XDG_RUNTIME_DIR:-/tmp}/claude-context-budget/$CLAUDE_CODE_SESSION_ID.budget"`. The PR moves the decisions into code and docs (the `hierarchical-documentation` pass). After the merge, append the piece to the session log (`orchestrator-status`), then run `plans close <id> --as <your session>`, which drops the id from every `depends_on` and deletes the doc and `.logs/<project>/<id>/`. Read a doc only for the section you act on (`plans show --section`).

Agents run in the background: after dispatching, end the turn and let the completion notice start the next one. Never poll, sleep or wait on an agent, and never state its result before the notice arrives. While waiting on the owner or a review, start read-only research for the next piece (in focus, only for a piece the owner assigned). The mode file `${XDG_RUNTIME_DIR:-/tmp}/claude-orch-mode/$CLAUDE_CODE_SESSION_ID` holds the mode as one word per line (`queue` or `auto`). No file or no `queue` word means focus. `queue` in `$ARGUMENTS` or the owner's "work the queue" adds the word, and "focus" removes it. Add with `f="${XDG_RUNTIME_DIR:-/tmp}/claude-orch-mode/$CLAUDE_CODE_SESSION_ID"; mkdir -p "$(dirname "$f")"; grep -qx queue "$f" 2>/dev/null || echo queue >> "$f"` and remove with `f="${XDG_RUNTIME_DIR:-/tmp}/claude-orch-mode/$CLAUDE_CODE_SESSION_ID"; sed -i '/^queue$/d' "$f"`, so other words stay. The `auto` word uses the same two commands with `auto` in place of `queue`. If the mode file holds `auto`, read `full-auto.md` beside this skill before acting. `/clear` changes the session id, so write the file again after one. In focus, work only on pieces the owner assigned or you already own. Skip the `work` lines and `ask #N` lines of `plans next` and the ask-which-piece rule below. With nothing in flight, give a short status and wait for the owner. Ask the owner each question `plans waiting` lists for a doc you own. In queue mode only: never end a turn idle with no piece in flight, ask the same for a doc nobody owns, and ask each `ask #N` line of `plans next`: where open issue N goes in the order, or that a closed issue N leaves the doc that ranks it. The answer is a body edit (`plans note`, or an agent for a rewrite): `- #N title` in the Plan of the covering doc, or of a new doc for the issue (made per the `issue-descriptions` skill), or the item removed, plus `plans set <id> issue=none` when the doc's `issue` key holds N. When the doc exists only for that issue, run `plans close <id> --as <your session>` instead. Meanwhile take up the `work` doc of `plans next --as <your session>` unasked (its rank is the owner's order) with `plans claim <id> --as <your session>`. If your agent already runs on it, rerun `plans next --as <your session> --skip <id>`. With no `work` line, ask which piece to take next. These asks are always allowed, never an escalation. Give each agent a short unique name for `SendMessage`. Every agent's report is yours to collect: on any agent notice that is not its report (interim, "waiting on its own background work", or silence), check its branch and worktree at once and tell the owner the state; never call an agent still working without checking.

Screenshots: never open an image yourself unless the owner asks. When a shot needs the owner's decision (look options, or a check the tools cannot settle), send its file to the owner with `SendUserFile` unopened, with the question in the same turn's brief.

Skills that only wrap a script: when you just need to run the script, read only that skill's `## Scripts` section (`awk '/^## Scripts/{f=1;next} /^#/{f=0} f' <SKILL.md>`) instead of loading the skill; load the whole skill when it has no such section, or when the script fails or the case isn't covered.

Review dimensions, used by every review below: correctness and regressions, missed requirements, scope (unrelated changes), reuse and unnecessary complexity, weak tests.

When the owner asks you to hand off, pass the baton or wind down, load `orchestrator-handoff`; for a status report (also due at each handoff and at wind-down), load `orchestrator-status`; a request to hand over from another session goes to the owner.

When the owner asks you to plan a fleet of orchestrators or an overnight run, load `fleet`.

## Start another orchestrator session

To start one more orchestrator in its own tmux window, write its prompt to a file and run:

`~/.claude/skills/orchestrator-handoff/spawn-orchestrator.sh <name> <prompt-file> [--model M] [--budget N]`

`<name>` is a session name like `df-help`. The window opens in your tmux session, in this repo's main checkout. Pass `--model` with the model the owner asked for. `--budget` is the context budget in tokens. The script sets no permission mode. For two or more full-auto sessions use `fleet`, not this script.

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
   - Once building, forks go to the owner. Batch them into one ask, briefed as above, and keep agents whose work does not depend on the answer running while you wait. A choice of yours that changes the design is a fork, not an "Assumed".

4. Delegate using the cheapest capable model:
   - Haiku only when the done check fits in one sentence and a wrong result is cheap to catch (a rename, a known small fix, a lookup); otherwise Sonnet. Haiku output that misses the bar goes to Sonnet, never back to Haiku.
   - Opus when Sonnet fails after a corrected retry, or for deep debugging or subtle correctness (concurrency, security, data integrity).
   - When work spans layers (a UI and a backend), agree the hand-off format first (an id, an API call, a JSON shape), then run one implementer per layer in parallel.
   - When the permission classifier denies an action, do not retry it in another form or via an agent; hand the owner the exact `!` command. Exception: if the denied call wrapped a script that has an allow rule, inside `$(...)`, after `&&`/`;`, or with a `VAR=x` prefix, rerun that script once as a bare command before handing the owner a command.

5. Give the implementer the worktree path, issue or PR, plan, constraints, relevant context, and validation requirements, through the piece's plan doc.
   - Run no check yourself. Each implementer and fixer brief states in one clause whether the repo's merge step runs the check. The worker runs the full check only where it does not.
   - For concurrency or lifecycle work (signals, locks, processes that hand over or race), name those risks in the brief. Review rounds otherwise find these bugs one at a time.
   - When agents run in parallel, each brief lists the files it owns, a "Do NOT" line naming what a sibling owns, and the shared code it must use rather than reimplement. Where siblings must share a file, run those agents one after another if the edits are more than small additions.

6. Never read a diff yourself. Brief a read-only reviewer agent with the review dimensions and the repository conventions, say whether it is a first or a follow-up review, and read its findings (verdict plus one line per finding).
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
   - Re-run the external review only for a material fix (a new mechanism, new concurrency or lifecycle code, or a rewrite of the reviewed logic); a targeted fix gets a reviewer agent's diff review (step 6), briefed as a follow-up review.

9. Final validation: the tree is clean, the worker's report shows the check passed on the final head (unless the repo's merge step runs the check), and a reviewer agent confirms the diff has nothing unrelated.

10. Create a PR against the appropriate base branch, or push to the existing PR's branch when working on one. Reference and close the issue, if one exists.

11. Run `~/.claude/skills/merge-prs/merge-prs.sh --check <pr>` (with `--skip-review-gate` for a trivial piece or one where the owner waived the reviewers) and resolve any thread or reviewer problem it reports. Only a passing check makes the PR ready.

12. Report: issue URL, PR URL, summary, validation, notable findings and dispositions (every declined thread listed), which reviewer ran (quoting the line Codex printed after `codex unavailable:`, if any), remaining risks, and whether it is ready for human review.
