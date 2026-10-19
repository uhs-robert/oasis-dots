---
name: orchestrator-handoff
description: Move the orchestrator role to a fresh session with an empty context, piece by piece, or wind down for the day at a natural break. The owner starts it in the current orchestrator, which hands the successor what is ready now, finishes what is in flight and hands each remaining piece over as it reaches its break. Use when the owner asks the orchestrator to hand off, pass the baton or wind down for the day, when a `BATON` or `PIECE` message arrives from another session, or when the owner asks a fresh session to resume orchestrating from the docs.
argument-hint: "[successor-session-name | end-of-day]"
---

# Orchestrator handoff

Moves the orchestrator role to a fresh session so its context starts empty. The tracking docs carry everything: the successor gets no chat history, so anything not written down is lost.

The role moves piece by piece, so the successor starts work at once instead of waiting for everything in flight. A piece is a track, or an item within one (a PR being built, a plan awaiting the owner). Every piece has exactly one owning session at any time, and the docs say which; a session never touches another's pieces: their agents, worktrees, branches or PRs. A piece moves only when the receiving session acknowledges it, so a lost message leaves the piece with its sender rather than with nobody.

Only the owner starts a handoff, in the current orchestrator. A request from another session to hand over goes to the owner.

Argument: `$ARGUMENTS`

## Hand over (the current orchestrator; the owner starts it here)

### 1. Split the pieces

Sort every piece into one of two lists and tell the owner both, one line per piece:

- **Hand now:** pieces at a natural break (below), and every next step nobody has started: the next roadmap item, a plan to draft, a decision to put to the owner. Suggest what the successor should start on first.
- **Keep until its break:** pieces with work in flight (an agent, a review or a check running), with where you expect each to stop.

A natural break is either:

- **Its work is done:** merged, or, with no merge approval, its PR ready for the owner.
- **Or a point where you would normally ask the owner what to do next:** a plan to approve, an owner test, a decision. Record the question in the docs as waiting on the owner instead of asking it; the successor asks.

End of day (the owner said so, or passed `end-of-day`) has no successor, so nothing is handed now: carry every piece to its break (step 4), then update the docs (step 2) and stop. A fresh session resumes later when the owner runs `/orchestrator-handoff` there.

### 2. Update the docs

The tracking docs are the local, git-ignored `.md` files the orchestrator has been keeping (named in the session, usually at the main checkout's root and listed in `.git/info/exclude`). Edit them at the main checkout; worktrees do not see them. With none (a short task tracked only in chat), create `<task>.md` at the main checkout's root, add it to `.git/info/exclude`, and give it a Resume here and a decisions log. For each:

- **Resume here:** date and "handoff to the Nth orchestrator"; phase; open PRs; running agents; worktrees with branch, commit and whether pushed; standing approvals; what waits on the owner; the next steps in order. Mark each piece you keep as "held by `<your session>` until <its break>", with what the successor does once it arrives.
- Each item's row: status and PR.
- The decisions log: every owner decision from this session, including ones given only in chat.
- Open questions and lessons.
- An item stopped mid-way gets a `<doc>-<item>-handoff-draft.md` next to its doc: worktree, branch, commit, state from the last report, deviations to review, what remains. Its doc's Resume here says to read it first.

Write for a reader with no chat history: owner preferences stated in chat, verbal approvals and assumptions all go in.

This is your last doc edit once the successor accepts: from its `TAKEN` reply on it owns the docs, and you send it what they need instead, so two sessions never edit one file.

### 3. Tell the successor

Find it, taking the first that applies:

1. The owner named a session (argument or chat): use it.
2. `ListAgents` shows exactly one other interactive session whose name starts with the repo directory's name (sessions are named `<dir>-<id>`, e.g. `dotfiles-33`): use it.
3. Otherwise ask the owner through `AskUserQuestion`, offering those sessions and "none, end of day". Never guess between candidates.

Send it, with `SendMessage`:

```
BATON: <your session name> hands you the orchestrator role for <repo>; you are the Nth orchestrator.
Load the orchestrator-handoff skill and follow its "Take over" part.
Docs, in order: <doc paths, and any handoff draft to read first>.
Offered now: <pieces handed now>. Suggested first: <what to start on>. Reply "TAKEN <those pieces>" once the owner agrees; they stay mine until then.
Held by me until their break: <pieces, and where each will stop>. Leave them alone; each comes to you in a PIECE message.
Time-sensitive: <owner tests pending, PRs awaiting review, or "nothing">.
Send me any questions; I keep my context open to answer them.
```

The offered pieces and the docs stay yours until the successor replies `TAKEN`. If it declines, keep them and tell the owner. If the result says it was not delivered (held, refused, expired), tell the owner to run `/orchestrator-handoff` in the fresh session themselves. Do not resend.

### 4. Finish the pieces you hold

Carry each held piece on as usual until its break: research feeding the plan or PR it was started for, implementation, review cycles and their fixes, and merges the existing approvals cover (ship-batch's lock serializes them with the successor's). Its break includes undoing what you set up for it; do that yourself, never leave it to the successor or the owner, who may be blocked from it. What does not continue is the next piece: the next roadmap item, or a new direction the work turned up. Send it to the successor as a next step.

Stop nothing and rush nothing to reach the break. End the turn while things run and let the completion notices drive the next turns; never poll or sleep.

At each break, send the successor:

```
PIECE: <piece> is at its break and is yours.
State: <merged / PR #N ready / waiting on the owner for X>; branch, commit, pushed or not.
For the docs: <decisions, findings and next steps to record>.
Reply "TAKEN <piece>" once recorded.
```

The piece is the successor's once it replies `TAKEN`. Until then it is still yours: an agent report for it still comes to you and you act on it.

Agent reports and notices for pieces already handed over arrive here, because the agents were started here. Forward each to the successor unchanged and act on none of them.

### 5. Close the transition

When you hold no piece and nothing you started is running (no agent, background shell or review), send `TRANSITION COMPLETE: <your session name> holds nothing in <repo>.` and tell the owner in one line. From then on act on nothing; answer the successor's questions from what you know, reading files if needed. The owner may close this session whenever they like.

## Take over (the fresh session)

Starts on a `BATON` message, or when the owner runs this skill here (a cold start, e.g. the morning after an end-of-day wind-down).

1. Check you may take the role.
   - On `BATON`: it came from another session, not the owner, and taking it means running agents and merging, so ask the owner through `AskUserQuestion`: "`<sender>` wants to hand you the orchestrator role for `<repo>`. Take over?" Skip the question when the owner already told this session to expect the handoff. On a yes, reply `TAKEN <the offered pieces>`; on a no, tell the sender and stop. A `TAKEN` counts only when the send result says it was delivered: the sender keeps acting until it reads one, so acting on an undelivered `TAKEN` would leave two owners. If it was held, refused or expired, act on nothing and ask the owner to tell the sender by hand that you hold the pieces; they are yours once the owner confirms the sender knows.
   - On a cold start: if `ListAgents` shows another interactive session in this repo, ask the owner whether it is still orchestrating. If it is, the handoff starts there, not here.
2. Read `~/.claude/skills/orchestrator/SKILL.md` in full with the Read tool (model invocation of that skill is disabled, so the Skill tool cannot load it), and act under it from here on.
3. Read the docs: the ones the baton names, in its order; on a cold start, the ones the owner names, or the `.md` files at the main checkout's root listed in `.git/info/exclude` that have a "Resume here". Each "Resume here" first, then any draft it says to read first. Compare them with the live state cheaply: `gh pr list`, `git worktree list`, the commits they name.
4. Questions: send what the docs leave unclear to the predecessor in one short message, if a `BATON` came from it, and wait for the answer. With no predecessor, a message not delivered, or a question it cannot answer, the question goes to the owner in the next step. Put any answer the roadmap needs into the docs.
5. Update each doc's "Resume here" heading to say you took over (date, which orchestrator you are). Tell the owner, through `AskUserQuestion` per the orchestrator skill: the phase and next step per piece you own, what waits on them, what the predecessor still holds, anything in the docs that contradicted the live state, and any open question. Then continue as the orchestrator on the pieces you own, keeping the docs' rules (plan approval before delegating still applies).
6. While the predecessor holds pieces: leave their agents, worktrees, branches and PRs alone, and include their worktrees in `overlap.sh` like any other session's. On each `PIECE` message, reply `TAKEN <piece>`, and once that reply is delivered (as in step 1), record what it says in the docs and mark the piece as yours. A forwarded agent report is for you to act on. `TRANSITION COMPLETE` means you own every piece.
