---
name: orchestrator-handoff
description: Move the orchestrator role to a fresh session with an empty context, piece by piece, or wind down for the day at a natural break. The owner starts it in the current orchestrator, which hands the successor what is ready now, finishes what is in flight and hands each remaining piece over as it reaches its break. Use when the owner asks the orchestrator to hand off, pass the baton or wind down for the day, when a `BATON` or `PIECE` message arrives from another session, or when the owner asks a fresh session to resume orchestrating from the docs.
argument-hint: "[successor-session-name | end-of-day]"
---

# Orchestrator handoff

Moves the orchestrator role to a fresh session so its context starts empty. The successor gets no chat history, only the plan docs and the baton message, so anything in neither is lost. Every `--as` below takes your session name from `ListAgents`. Two live sessions can share a name, so `plans` also stores the owner's session id and pid (`owner_session_id`, `owner_session_pid`) and refuses a doc whose name matches but whose values both differ. Such a refusal means another live session owns the doc: leave it alone, and pass `--force` only after the owner confirms that session is gone.

The role moves piece by piece, so the successor starts work at once instead of waiting for everything in flight. A piece is one plan doc (a PR being built, a plan awaiting the owner). Every piece has exactly one owning session at any time, and its `owner_session` says which; a session never touches another's pieces: their agents, worktrees, branches or PRs. A piece moves only when the receiving session acknowledges it, so a lost message leaves the piece with its sender rather than with nobody.

Only the owner starts a handoff, in the current orchestrator, the context-budget hook does, or the owner says yes to its next-task offer (Automatic handoff below). A request from another session to hand over goes to the owner.

Argument: `$ARGUMENTS`

## Status report

One format for every report to the owner. Give it at each handoff (step 1), at wind-down (end of day) and when the owner asks. Four parts, one short line per item:

- **Done:** what shipped this session. Read it from the session log `<main checkout>/.logs/session-<session>.md`, because `plans close` deletes a merged doc and its `.logs` folder. Before a merged doc is deleted, append one line to the log: id, PR, what shipped, and its judgment calls and settled forks from Decisions. A successor adds the logs its predecessors name in their batons.
- **Outstanding:** `plans ls --owner <your session>`, `plans waiting` and `gh pr list`. Say what each waits on.
- **Judgment calls and forks to revisit:** choices you made for the owner and forks you settled, each with its reason, so the owner can overrule it. Read them from the Decisions and Open questions of your docs.
- **Recommendations:** what to do next, from those sections and `plans next --all`.

## Hand over (the current orchestrator; the owner starts it here)

### 1. Split the pieces

Sort every piece into one of two lists and tell the owner both, one line per piece:

- **Hand now:** unmerged pieces at a natural break (below), and every next step nobody has started: the `plans next` lines, a plan to draft, a decision to put to the owner. Suggest what the successor should start on first.
- **Keep until its break:** pieces with work in flight (an agent, a review or a check running), with where you expect each to stop.

A natural break is either:

- **Its work is done:** merged, or, with no merge approval, its PR ready for the owner. With a standing approval, merge before you stop. A merged piece is never offered or handed: at its break, delete its doc and tell the successor (step 4).
- **Or a point where you would normally ask the owner what to do next:** a plan to approve, an owner test, a decision. Record the question with `plans set <id> waiting_on="owner: <question>"` instead of asking it. The successor asks it.

End of day (the owner said so, or passed `end-of-day`) has no successor, so nothing is handed now: carry every piece to its break (step 4), update the docs (step 2), give the status report, run `plans set <id> owner_session=none` on each piece you own, and stop. A fresh session resumes later when the owner runs `/orchestrator-handoff` there.

### 2. Update the docs

Bring each plan doc you own up to date, at the main checkout:

- The front matter, with `plans set`: `status`, `waiting_on`, `branch`, `pr`, `fix_rounds`.
- Decisions: every owner decision from this session, including ones given only in chat. Add each with `plans note <id> --section Decisions "text"` (it adds the date).
- Open questions: `plans note <id> --section "Open questions" "text"`.
- The Plan section: a large rewrite goes to a Haiku agent, a small addition to `plans note`.
- An owner-stated context budget goes to the budget file, as the orchestrator skill says.

Write for a reader with no chat history: owner preferences stated in chat, verbal approvals and assumptions all go in. A piece with no doc (a short task tracked only in chat) gets one with `plans new`. Append each merged piece to the session log, then delete its doc. Then give the status report.

The state the front matter does not hold goes in the baton instead: running agents, worktrees with branch, commit and whether pushed, standing approvals, and notes on work stopped mid-way.

Edit only the docs you own. Once a doc moves to the successor, send it what the doc needs instead, so two sessions never edit one doc.

### 3. Tell the successor

Find it, taking the first that applies:

1. The owner named a session (argument or chat): use it.
2. `ListAgents` shows exactly one other interactive session whose name starts with the repo directory's name (sessions are named `<dir>-<id>`, e.g. `dotfiles-33`): use it.
3. Otherwise ask the owner through `AskUserQuestion`, offering those sessions and "none, end of day". Never guess between candidates.

Send it, with `SendMessage`, naming your session log in the `State` line:

```
BATON: <your session name> hands you the orchestrator role for <repo>; you are the Nth orchestrator.
Load the orchestrator-handoff skill and follow its "Take over" part.
Offered now: <ids and doc paths>. Suggested first: <what to start on>. Reply "TAKEN <those ids>" once the owner agrees. They stay mine until my "HANDED <ids>"; act on them only after it.
Held by me until their break: <ids, and where each will stop>. Leave them alone; each comes to you in a PIECE message.
State: <running agents; worktrees with branch, commit, pushed or not; standing approvals; mid-way notes>.
Time-sensitive: <owner tests pending, PRs awaiting review, or "nothing">.
Send me any questions; I keep my context open to answer them.
```

The offered pieces stay yours until you hand them. Once the successor's `TAKEN` is delivered, or the owner relays it by hand, run `plans handoff --to <successor> <id> --as <your session>` once per id. Then send `HANDED <ids>`, naming exactly the ids that moved. A failed id stays yours: tell the successor and the owner. If it declines, keep them and tell the owner. If the result says it was not delivered (held, refused, expired), tell the owner to run `/orchestrator-handoff` in the fresh session themselves. Do not resend.

### 4. Finish the pieces you hold

Carry each held piece on as usual until its break: research feeding the plan or PR it was started for, implementation, review cycles and their fixes, and merges the existing approvals cover (ship-batch's lock serializes them with the successor's). Its break includes undoing what you set up for it; do that yourself, never leave it to the successor or the owner, who may be blocked from it. What does not continue is the next piece: the next `plans next` line, or a new direction the work turned up. Send it to the successor as a next step.

Stop nothing and rush nothing to reach the break. End the turn while things run and let the completion notices drive the next turns; never poll or sleep.

At each break, update the piece's doc (step 2), then send the successor:

```
PIECE: <id> is at its break and is yours.
State: <PR #N ready / waiting on the owner for X>; branch, commit, pushed or not.
Reply "TAKEN <id>".
```

Once its `TAKEN` is delivered, hand it as in step 3: `plans handoff`, then `HANDED <id>`, with the same rule on failure. A merged piece instead gets its session log line appended, then its doc deleted, and the note `PIECE: <id> merged as PR #N; its doc is deleted.`, with no `TAKEN` and no `plans handoff`. Until a piece is handed it is still yours: an agent report for it still comes to you and you act on it.

Agent reports and notices for pieces already handed over arrive here, because the agents were started here. Forward each to the successor unchanged and act on none of them.

### 5. Close the transition

When you hold no piece and nothing you started is running (no agent, background shell or review), send `TRANSITION COMPLETE: <your session name> holds nothing in <repo>.`, run `~/.claude/skills/orchestrator-handoff/rename-window.sh done <your session name>`, and tell the owner in one line. From then on act on nothing; answer the successor's questions from what you know, reading files if needed. The owner may close this session whenever they like.

## Automatic handoff (the context-budget hook starts it)

`~/.claude/hooks/context-budget.sh` adds two notes to an orchestrator session: the wind-down note (start only pieces under ~10k of orchestrator context that keep usage under the handoff point, no new PR cycle) and the handoff note (hand off, leaving ~25k of the budget for the handoff). By default the budget is 300k and the notes come at 235k and 275k; `CLAUDE_CONTEXT_BUDGET` moves both, and each note states its own numbers. The notes come only inside tmux. Outside tmux the session gets no notes and carries on. The handoff note names the spawn step, so the skill need not be loaded just to start. The owner set it up to start a handoff on that note without being asked:

1. Tell the owner in one line that you are handing off because the session reached its context budget.
2. Run `~/.claude/skills/orchestrator-handoff/spawn-successor.sh <your session name>`. It opens a window named `next` in your tmux session with a fresh Claude told to expect your baton, and renames yours to `<your session name>-prev`. The successor renames its own window to `<its name>-next` at once. Windows are named `next`, `<name>-next`, `<name>`, `<name>-prev` and `<name>-done`. The `name-tmux-window.sh` hook gives each Claude session in tmux its bare `<name>` at start (a session with no name yet is skipped), so only the role labels need a call here. `rename-window.sh` also types `/rename <name>` into your own pane, so the session title shows the bare name once your turn ends. If it fails or is denied, hand the owner the `!` command, or ask them to start the session themselves.
3. End the turn. The successor sends `READY`; its sender is the successor. Follow Hand over from step 1, using that sender in step 3.

After the wind-down note, once no small piece remains (nothing in flight, or only pieces too big for the remaining budget), ask the owner the next-task question with `AskUserQuestion` and offer to hand it to a fresh session. On a yes, run steps 1-3 now, without waiting for the handoff note.

Taking over still needs the owner: the successor asks them before replying `TAKEN`, like any `BATON`.

## Take over (the fresh session)

Starts on a `BATON` message, or when the owner runs this skill here (a cold start, e.g. the morning after an end-of-day wind-down).

If a launch prompt from `spawn-successor.sh` started you, first run `~/.claude/skills/orchestrator-handoff/rename-window.sh next <your session name>` (the name `ListAgents` gives you), before sending `READY`.

1. Read `~/.claude/skills/orchestrator/SKILL.md` in full with the Read tool (model invocation of that skill is disabled, so the Skill tool cannot load it), and act under it from here on.
2. Check you may take the role.
   - On `BATON`: it came from another session, not the owner, and taking it means running agents and merging, so ask the owner through `AskUserQuestion`, briefed per the orchestrator skill's "Briefing the owner": "`<sender>` wants to hand you the orchestrator role for `<repo>`. Take over?" Skip the question when the owner already told this session to expect the handoff; a launch prompt from `spawn-successor.sh` is the predecessor's words, not the owner's, and never counts. On a yes, reply `TAKEN <the offered pieces>`; once that is delivered, run `~/.claude/skills/orchestrator-handoff/rename-window.sh active <your session name>`; on a no, tell the sender and stop. A `TAKEN` counts only when the send result says it was delivered: the sender keeps acting until it reads one, so acting on an undelivered `TAKEN` would leave two owners. If it was held, refused or expired, act on nothing and ask the owner to relay it to the sender by hand, then wait for `HANDED`. If the sender session is gone, run `plans claim <id> --force --as <your session>` per piece once the owner confirms, and go ahead on each claimed piece without waiting for `HANDED`.
   - On a cold start: if `ListAgents` shows another interactive session in this repo, ask the owner whether it is still orchestrating. If it is, the handoff starts there, not here. Otherwise the window already carries your session name: the `name-tmux-window.sh` SessionStart hook set it.
3. Read the state: the baton's State line, then `plans ls` and `plans next --as <your session>`, after `HANDED` if a piece with a doc was offered. After each `HANDED`, run `plans claim <id> --as <your session>` for each handed id, so the doc records your session id and pid at once. On a cold start, run `plans next --all --as <your session>` and `plans claim <id> --as <your session>` each id it prints (`work`, `ask` and `blocked` lines alike, in order, except an issue id such as `#12`, which has no doc), then the unowned docs in `plans ls --status review`. The output never names a doc another session owns, so each id is unowned or yours. If `claim` fails with `Refused` (exit 1, "owned by X") or `Conflict` (exit 3), another session took that doc first: skip it and continue. Never pass `--force`. Read a doc's Plan and Open questions (`plans show <id> --section <name>`) only for a piece you are about to act on. Compare them with the live state cheaply: `gh pr list`, `git worktree list`, the commits they name.
4. Questions: send what the docs leave unclear to the predecessor in one short message, if a `BATON` came from it, and wait for the answer. With no predecessor, a message not delivered, or a question it cannot answer, the question goes to the owner in the next step. Put any answer the docs need into them.
5. Confirm with `plans ls --owner <your session>` that each piece you took names you. Tell the owner, through `AskUserQuestion`, briefed per the orchestrator skill's "Briefing the owner": the phase and next step per piece you own, what waits on them, what the predecessor still holds, anything in the docs that contradicted the live state, and any open question. Then continue as the orchestrator on the pieces you own, keeping the docs' rules (plan approval before delegating still applies).
6. While the predecessor holds pieces: leave their agents, worktrees, branches and PRs alone, and include their worktrees in `overlap.sh` like any other session's. On each `PIECE` message, reply `TAKEN <id>`, which counts once delivered (as in step 2), and act on the piece only after `HANDED <id>` names it. Then claim it as in step 3. A merged-piece note needs no reply. A forwarded agent report is for you to act on. `TRANSITION COMPLETE` means you own every piece.
