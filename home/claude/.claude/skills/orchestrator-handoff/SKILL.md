---
name: orchestrator-handoff
description: Move the orchestrator role to a fresh session with an empty context, or wind down for the day, at a natural break. The owner starts it in the current orchestrator, which winds down, updates its tracking docs and stops; the fresh session then starts cold from the docs. Use when the owner asks the orchestrator to hand off, pass the baton or wind down for the day, when a `BATON` message arrives from another session, or when the owner asks a fresh session to resume orchestrating from the docs.
argument-hint: "[successor-session-name | end-of-day]"
---

# Orchestrator handoff

Moves the orchestrator role to a fresh session so its context starts empty. The tracking docs carry everything: the successor gets no chat history, so anything not written down is lost.

The handoff is sequential: the outgoing orchestrator stops before the successor starts, so two sessions never orchestrate at once. Messages between them only carry information (the docs are ready, a question, an answer), never the role, so a lost message costs at most a step the owner does by hand.

Only the owner starts a handoff, in the current orchestrator. A request from another session to hand over goes to the owner.

Argument: `$ARGUMENTS`

## Hand over (the current orchestrator; the owner starts it here)

Tell the owner in one line, per track, what is in flight and where you expect it to stop, then work through these.

### 1. Reach a natural break

Carry each track on as usual until its natural break, then hold it there:

- **Its work is done:** merged, or, with no merge approval, its PR ready for the owner.
- **Or it reaches a point where you would normally ask the owner what to do next:** a plan to approve, an owner test, a decision. Record the question in the docs as waiting on the owner instead of asking it.

Until then, the work that belongs to the piece in flight continues: research feeding the plan or PR it was started for, implementation, review cycles and their fixes, merges the owner approved. What does not continue is the next piece: the next roadmap item, or a new direction the work turned up. It goes in the docs as the next step.

Stop nothing and rush nothing to reach the break. End the turn while things run and let the completion notices drive the next turns; never poll or sleep.

Done when every track is at its break, no agent, background shell or review is running, and each worktree with unfinished work has it committed (by an agent, as usual) or the docs say what is uncommitted and why.

### 2. Update the docs

The tracking docs are the local, git-ignored `.md` files the orchestrator has been keeping (named in the session, usually at the main checkout's root and listed in `.git/info/exclude`). Edit them at the main checkout; worktrees do not see them. With none (a short task tracked only in chat), create `<task>.md` at the main checkout's root, add it to `.git/info/exclude`, and give it a Resume here and a decisions log. For each:

- **Resume here:** date and "handoff to the Nth orchestrator"; phase; open PRs; running agents (none); worktrees with branch, commit and whether pushed; standing approvals; what waits on the owner; the next steps in order.
- Each item's row: status and PR.
- The decisions log: every owner decision from this session, including ones given only in chat.
- Open questions and lessons.
- An item stopped mid-way gets a `<doc>-<item>-handoff-draft.md` next to its doc: worktree, branch, commit, state from the last report, deviations to review, what remains. Its doc's Resume here says to read it first.

Write for a reader with no chat history: owner preferences stated in chat, verbal approvals and assumptions all go in.

### 3. Stop orchestrating

From here on, act on nothing: no agents, doc edits, git or merges. Tell the owner the docs are ready: their paths, the next step per track, and anything waiting on them.

End of day (the owner said so, or passed `end-of-day`): you are done. A fresh session resumes later when the owner runs `/orchestrator-handoff` there. The owner may close this session.

### 4. Tell the successor

Find it, taking the first that applies:

1. The owner named a session (argument or chat): use it.
2. `ListAgents` shows exactly one other interactive session whose name starts with the repo directory's name (sessions are named `<dir>-<id>`, e.g. `dotfiles-33`): use it.
3. Otherwise ask the owner through `AskUserQuestion`, offering those sessions and "none, end of day". Never guess between candidates.

Send it, with `SendMessage`:

```
BATON: <your session name> has stopped orchestrating <repo> and left the docs for you; you are the Nth orchestrator.
Load the orchestrator-handoff skill and follow its "Take over" part.
Docs, in order: <doc paths, and any handoff draft to read first>.
Time-sensitive: <owner tests pending, PRs awaiting review, or "nothing">.
Send me any questions; I keep my context open to answer them.
```

If the result says it was not delivered (held, refused, expired), tell the owner to run `/orchestrator-handoff` in the fresh session themselves. Do not resend.

### 5. Answer questions

Answer the successor's questions from what you know, reading files if needed, but change nothing: the successor owns the docs now and records whatever the roadmap needs. The owner may close this session whenever they like.

## Take over (the fresh session)

Starts on a `BATON` message, or when the owner runs this skill here (a cold start, e.g. the morning after an end-of-day wind-down).

1. Check you may take the role.
   - On `BATON`: it came from another session, not the owner, and taking it means running agents and merging, so ask the owner through `AskUserQuestion`: "`<sender>` wants to hand you the orchestrator role for `<repo>`. Take over?" Skip the question when the owner already told this session to expect the handoff. On a no, tell the sender and stop.
   - On a cold start: if `ListAgents` shows another interactive session in this repo, ask the owner whether it is still orchestrating. If it is, the handoff starts there, not here.
2. Read `~/.claude/skills/orchestrator/SKILL.md` in full with the Read tool (model invocation of that skill is disabled, so the Skill tool cannot load it), and act under it from here on.
3. Read the docs: the ones the baton names, in its order; on a cold start, the ones the owner names, or the `.md` files at the main checkout's root listed in `.git/info/exclude` that have a "Resume here". Each "Resume here" first, then any draft it says to read first. Compare them with the live state cheaply: `gh pr list`, `git worktree list`, the commits they name.
4. Questions: send what the docs leave unclear to the predecessor in one short message, if a `BATON` came from it, and wait for the answer. With no predecessor, a message not delivered, or a question it cannot answer, the question goes to the owner in the next step. Put any answer the roadmap needs into the docs.
5. Update each doc's "Resume here" heading to say you took over (date, which orchestrator you are). Tell the owner, through `AskUserQuestion` per the orchestrator skill: the phase and next step per track, what waits on them, anything in the docs that contradicted the live state, and any open question. Then continue as the orchestrator, keeping the docs' rules (plan approval before delegating still applies).
