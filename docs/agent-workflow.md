# Agent workflow

The agent workflow is how Claude sessions plan, build, review and merge work in this repo, with the owner approving at set points. This guide shows how the parts fit. Each part has its own doc, linked in the code map at the end.

## The parts

- A plan doc is one file per piece of active work, at `.plans/<project>/<id>.md` in the main checkout. It holds the plan, the decisions and the state of the piece in its front matter. The `.plans/` and `.logs/` folders are gitignored.
- The `plans` command reads and edits plan docs. Every write goes through one safe write path (below).
- The board is `plans serve`, a web page over the plan docs of every repo on the machine. It runs as the user service `plans-serve`.
- The orchestrator is a session that delegates all hands-on work to agents. It plans, briefs, reads reports and talks to the owner.
- The interview skill turns a loose request into a plan that the owner approves.
- The orchestrator-handoff skill moves the orchestrator role to a fresh session.
- The ship-batch skill is the only way to merge a PR.
- Two hooks watch the sessions: `context-budget.sh` warns an orchestrator about its context size, and `guard-git-stash.sh` blocks `git stash` for subagents.

## The life of a piece

The `status` key of a plan doc follows this path:

1. `idea`: `plans new <project> <id>` writes the doc. The orchestrator runs it.
2. `planned`: the plan is drafted and awaits the owner. The interview skill or the orchestrator sets it.
3. `approved`: the owner approved the plan. The orchestrator or the interview skill sets it.
4. `building`: an agent works on it. The orchestrator sets it at dispatch.
5. `review`: the PR is open. The orchestrator sets it. Reviewers check it, and fix rounds follow (`fix_rounds` counts them, 2 at most without the owner).
6. `done`: no session sets it in practice. After the merge, an agent drops the id from every `depends_on`, then deletes the doc and its `.logs` folder.

A piece can also be `blocked` or `parked`, on the owner's word. While a question waits for the owner, `waiting_on` holds `owner: <question>`, and the orchestrator clears it after the answer.

The doc is for active work only, and GitHub issues stay the backlog of problems. Before the doc is deleted, the PR moves anything lasting into the repo. The rule is in the Docs section of [`AGENTS.md`](../AGENTS.md).

`.logs/<project>/<id>/` holds the evidence of a piece: check output, review notes and PR bodies. Agent reports stay short and point to files there.

## Ownership

Every piece has one owning session, named in `owner_session`, or `none`. A session never touches the agents, worktrees, branches or PRs of a piece that another session owns.

- `plans claim <id> --as <session>` takes a free doc.
- `plans next --as <session>` shows what to do next, by `rank` (the owner's order).
- `plans handoff --to <session> <id>` moves a doc to another session.
- `--force` overrides an owner. Use it only with the owner's word.

Two writers can race on one doc, for example an agent and the board. The write path reads the doc, locks `.plans/`, reads it again and compares the keys it changes. If another writer changed one of them, the write stops with exit code 3 and leaves the file as it was. Writes to different keys both land.

## Handoff

The orchestrator hands its role to a fresh session so its context starts empty. The owner starts a handoff, or the `context-budget.sh` hook does when the context nears its budget (300k by default, set with `CLAUDE_CONTEXT_BUDGET`). The hook only runs inside tmux.

The role moves piece by piece, with four messages:

1. `BATON`: the current orchestrator lists the pieces it offers, the pieces it holds until their break and the live state. The successor asks the owner before it takes the role.
2. `TAKEN <ids>`: the successor accepts the offered pieces.
3. `HANDED <ids>`: the sender has run `plans handoff` for those ids. From now on the successor owns them.
4. `PIECE <id>`: a held piece reached its break and is offered. It follows the same `TAKEN` and `HANDED` steps.

A piece moves only when the receiver acknowledges it, so a lost message leaves the piece with its sender. The sender sends `TRANSITION COMPLETE` when it holds nothing. The steps are in the orchestrator-handoff skill.

## The board

Start it with `systemctl --user enable --now plans-serve` and open http://127.0.0.1:8765. It shows a column per status and a lane per repo. The cards come from the plan docs, so the board and the CLI never disagree. The board edits only status, owner and rank, through the same write path as `plans set`. Keys and limits are in the `plans` README.

## Decisions

These choices from the design stay in force:

- There is no tracker, no index file and no decision archive. Notes for the next orchestrator go in the baton message.
- The front matter is a strict subset of YAML (flat `key: value` lines and `[a, b]` lists), and `plans lint` enforces it. The `plans` README lists the keys.
- Every doc has the sections Goal, Decisions (dated), Plan, Open questions and Owner checks. An answered question moves into Decisions.
- The `plans` CLI is Python 3 with the standard library only. It is a small library plus a thin command layer, and the board reuses the library.
- `plans lint` stays offline. `plans lint --gh` also asks GitHub, for example for a merged PR whose doc remains.
- The file `~/.config/plans/roots` lists the repo roots to scan, so `--all` works across repos.
- `guard-git-stash.sh` blocks `git stash` for subagents. All worktrees of a repo share one stash stack, and a subagent once dropped the stash of another worktree. The hook message names the safe options: `git show <commit>:<path>` to test old code, a commit before a merge, and a temporary worktree for throwaway work.

## Code

| Part | Path | Doc |
| --- | --- | --- |
| `plans` CLI and library | `home/plans/.local/bin/plans`, `home/plans/.local/lib/plans/plans/` | [`home/plans/README.md`](../home/plans/README.md) |
| Board | `home/plans/.local/lib/plans/plans/server.py`, `board.html` | the Serve section of the same README |
| Board service | `home/plans/.config/systemd/user/plans-serve.service` | the Serve section, and the unit comments |
| `plans` tests | `home/plans/tests/` | the same README; [`lib/check/README.md`](../lib/check/README.md) |
| Stow package `plans` (in CORE) | `packages/stow.ini`, `lib/install/stow.sh` | [`lib/install/README.md`](../lib/install/README.md) |
| Orchestrator skill, reviewers | `home/claude/.claude/skills/orchestrator/` | its `SKILL.md` and `reviewers.md` |
| Handoff skill and its scripts | `home/claude/.claude/skills/orchestrator-handoff/` | its `SKILL.md` |
| Interview skill | `home/claude/.claude/skills/interview/` | its `SKILL.md` |
| Merging | `.claude/skills/ship-batch/` | its `SKILL.md`; the Merging section of [`AGENTS.md`](../AGENTS.md) |
| Context budget hook | `home/claude/.claude/hooks/context-budget.sh` | the header comment |
| Git stash hook | `home/claude/.claude/hooks/guard-git-stash.sh` | the header comment |
| Plan doc layout | `.gitignore` | the Docs section of [`AGENTS.md`](../AGENTS.md) |
