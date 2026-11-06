# plans

`plans` reads and edits the front matter of the plan docs under `.plans/`. Each doc is one piece of active work, at `.plans/<project>/<id>.md` in the main checkout of a repo. `plans` replaces the tracker files, and `plans serve` shows every repo's docs on a web board.

Stow the package with `just stow plans` (it is in the core list). The command lands in `~/.local/bin/plans`. It needs Python 3 and nothing else.

## Usage

Run `plans` anywhere in a repo or one of its worktrees. It always reads the main checkout, because worktrees do not see the git-ignored `.plans/`.

```bash
plans ls [--owner S] [--project P] [--status a,b] [--all] [--json]   # one line per doc
plans next [--as S] [--skip ID]... [--all] [--json]   # issue ask lines, doc ask and blocked lines, then one work line; --all lists every free doc of this repo
plans waiting [--all] [--json]        # docs with a non-empty waiting_on
plans questions [--all] [--json]      # the unchecked "- [ ]" items under Open questions
plans show <id> [--section NAME] [--json]
plans set <id> key=value...           # e.g. plans set demo status=building depends_on=a,b
plans claim <id> [--as S] [--force]   # owner_session = S
plans handoff --to T <id>... [--as S] [--force]
plans new <project> <id> [--kind K]   # writes .plans/<project>/<id>.md, kind feature by default
plans lint [--gh] [--all]
plans serve [--port N]                # the web board, see below
```

A line holds tab-separated columns: the repo (only with `--all`), id, status, owner, rank and waiting_on. `--json` prints the full front matter of each doc, plus its `path`.

On `ls`, `waiting`, `questions` and `lint`, `--all` reads every repo under the directories in `~/.config/plans/roots`, one per line. Without that file, the roots are `$GITHUB_DIR` (default `~/Development`) and the dotfiles checkout, found through the `~/.local/share/dotfiles/repos` link. A root that is a git repo counts as one repo. Any other root is searched three levels down, and the search stops at each repo it finds.

`--as` names the session, for example `dotfiles-56`. `$PLANS_SESSION` is the fallback. `claim` and `handoff` need one of the two.

Two live sessions can get the same name, so a doc also records the owner's `$CLAUDE_CODE_SESSION_ID` and `$CLAUDE_PID` in `owner_session_id` and `owner_session_pid`. A session with the owner's name owns the doc when either value matches its own. The id changes on `/clear` and the pid on `--resume`. When both stored values differ, another session holds the name: `claim` and `handoff` refuse the doc, and `next` skips it. A `claim` writes the caller's values. A `set` refreshes both when either one matches the caller's. So a `/clear` and then a resume never lock the owner out while it writes in between. A shell without the two variables matches by name only and leaves the values as they are.

- `next` walks the docs with status planned, approved or building, lowest rank first. It skips each doc that another session owns. Each doc above the first free doc gets a line. A doc that waits on the owner gets an `ask` line, and a doc with an unfinished dependency gets a `blocked` line. Then it prints one `work` line for the first free doc. On `next`, `--all` does not scan other repos. It stays in the current repo and prints a `work` line for every free doc, in rank order, and a doc that depends on a free doc stays `blocked` until that doc is done. `--skip` leaves a doc out, for example one an agent already works on, but a skipped doc still blocks the docs that depend on it. A free doc has an empty `waiting_on` and no unfinished `depends_on` entry. A dependency is finished when its doc is done or gone, because a merged piece deletes its doc. A dependency whose doc cannot be read blocks, as `blocked by <id> (unreadable)`.
- `next` first prints an `ask` line for each open GitHub issue that no doc ranks, and one for each ranked issue that is closed. See [Issue ranks](#issue-ranks).
- `claim` and `handoff` refuse a doc that another session owns. `--force` overrides that. A forced `claim` writes the caller's values. `handoff` checks every listed doc before it writes any of them. Every `handoff` clears both values, forced or not, and the receiver's first `claim` writes its own.
- `set` refuses `id`, `project`, `updated`, `owner_session_id` and `owner_session_pid`, a value with a line break, an unknown key, and a value outside a closed set. A list takes `a,b` or `[a, b]`.
- `new` gives the doc every key, `status: idea`, a rank 10 past the last-ranked doc, and the five empty sections. It never overwrites a doc. It refuses an id the repo already uses, and the project name `projects` of the old layout.
- `lint` checks every rule below and prints `path:line: rule: message`. `lint --gh` also asks GitHub, through the `gh` CLI, for a merged or closed `pr`, a closed `issue` and a `branch` the remote no longer has.
- `ls` and `lint` name each old layout and say "migrate this repo". The old layouts are `.planning/roadmap.md`, `.plans/roadmap.md`, `.plans/projects/` and root `.md` files that `info/exclude` hides. A doc with the old `kind: plan`, `tracker` or `handoff` counts too, and `ls` skips it.

| Exit code | Meaning |
| --- | --- |
| 0 | done |
| 1 | lint findings, or a refused request |
| 2 | bad input, or a missing doc |
| 3 | the doc changed since it was read |

### Two writers

Every write reads the doc, locks `.plans/`, reads it again and compares the keys it changes. If another writer changed one of them in between, the write stops with exit code 3 and leaves the file as it was. Writes to different keys both land. A body edit counts as a change to the key `body`. The `updated` key never conflicts, because every write sets it to today. The write edits only the changed front matter lines and keeps the body bytes as they were.

## Issue ranks

Every open GitHub issue of a repo needs a rank. A doc ranks an issue when its `issue` key holds the number (`12`, `#12` or the issue URL), or its `## Plan` section names it as `#12`. Other sections hold history, so `#12` there does not count, and neither does `other/repo#12`. Issues that no feature doc covers go in the repo's `follow-ups` doc, one `- #12 title` item per line, in rank order. Give that doc status `planned`, so `next` walks it at its rank.

`plans next` prints the gaps before its other lines:

```
ask	#1465	rank: plain-writing lint: rare shell forms still hide or invent PR bodies
ask	#94	closed: drop it from follow-ups
```

A `rank` line is an open issue that no doc ranks. A `closed` line names the first doc by rank that still ranks a closed issue. With `--json`, these rows carry `"issue": N`, and `path` is the doc, or null. The check only reports. It never edits a doc.

The repo comes from the `origin` remote, so a repo without a GitHub origin gets no check and no network call. The answers from `gh` are cached in `$XDG_CACHE_HOME/plans/<owner>/<repo>.json` (default `~/.cache`, readable by you only) for 10 minutes, and a ranked number the cache does not know fetches again. Each `gh` call gets 5 seconds. When `gh` is missing or fails, `next` uses the old cache, and without one it prints no issue lines. After a failure, `next` waits a minute before it asks `gh` again, so an offline `next` pays the timeout once. Delete the file to fetch at once.

## Serve

`plans serve` runs a web board over the docs of every repo under the roots, the same repos as `--all`. Open http://127.0.0.1:8765 in a browser. It needs nothing beyond Python 3.

In Hyprland, `SUPER + A`, then `K` opens the board, starting the service first when the port is closed.

To run it in the background with every graphical session, enable the user service. `just stow plans` installs it, but nothing enables it:

```bash
systemctl --user enable --now plans-serve
```

The service is wanted by `graphical-session.target`, so it starts and stops with that target. A text-only or SSH login does not start it.

The service does not see a `GITHUB_DIR` that only the shell exports. Without the roots file (`~/.config/plans/roots`, one directory per line) it uses the default roots and can miss repos that `plans ls --all` finds. The file replaces the defaults, so list every root in it, including the dotfiles checkout.

The board has a column per status and a lane per repo, then per project. The header holds a repo search box and filters for the id, owner, project, status, kind and waiting on the owner. A card shows the id, kind, owner, rank, `waiting_on`, the PR link and a badge per `depends_on` entry. A doc outside the front matter subset shows as a red error card. The board refreshes within a second when an agent changes a doc, and it finds a new repo within 30 seconds.

| Key | Action |
| --- | --- |
| `j` `k` | the next or previous card in the column |
| `h` `l` | the nearest card in the column to the left or right |
| `H` `L` | move the card one status column; a move to blocked or done asks `y` / `n` |
| `J` `K` | move the card one place down or up in its cell (its rank) |
| `e` | edit the owner: a session name or `none` |
| `o`, Enter | open the doc in `$EDITOR` in a new terminal |
| double-click a card | the same as `o` (not on the owner badge or a link) |
| `/` | the id filter; Esc goes back to the board |
| `r` | the repo search box |

The repo search box lists the repos that have plan docs, with all repos first. Typing keeps the repos whose `owner/name` label or folder name holds the letters in order, best match first, and a hit at a word start or in a run ranks higher. Arrow keys move the highlight, Enter or a click picks, Esc closes the list, and Tab leaves without a pick. Pick all repos, or empty the box and press Esc, to clear the filter. The pick does not survive a page reload. The matcher has a node test: `node home/plans/tests/fuzzy.test.mjs`. `tests/test_board_fuzzy.py` runs it in the `plans` check step.

A drag moves a card within its lane, to another status, another place or both. A drop takes the midpoint of the ranks around it. When there is no gap, the board renumbers the repo in steps of 10.

Each write goes through the same safe write path as `plans set`, and the board compares against the values it showed. If an agent changed one of those keys since the board last loaded, the write is refused. The card snaps back and a message names the keys. A renumber skips a doc that an agent re-ranked meanwhile, keeps the agent's rank and says which doc it skipped. Status and owner follow the rules of `plans set`. The other keys are read-only on the board.

`o` uses the terminal launcher that the Hyprland config writes (`~/.local/state/hypr/bin/term`), else `$TERMINAL`. The editor is `$VISUAL`, then `$EDITOR`, then `nvim`. The user service does not see the shell's `$EDITOR`; if it should differ, run `systemctl --user set-environment EDITOR=...`, then `systemctl --user restart plans-serve`, because the setting reaches only processes that start later. `VISUAL` wins over `EDITOR`, so set `VISUAL` instead if the manager already has one.

The board listens on 127.0.0.1 only and has no login. It refuses a request whose Host header is not `127.0.0.1` or `localhost` on its port. A write also needs the board's own request header, so a page on another site cannot write.

## Front matter

```yaml
---
id: agent-workflow-plans-cli
project: agent-workflow
kind: feature
status: building
owner_session: dotfiles-56
rank: 10
depends_on: [other-id]
waiting_on: "owner: pick a colour"
issue: none
pr: 12
branch: feat/plans-cli
fix_rounds: 0
updated: "2026-11-05"
---
```

| Key | Value |
| --- | --- |
| `id` | the file name without `.md`, unique in the repo |
| `project` | the folder under `.plans/` |
| `kind` | feature, bug, refactor, docs, chore, research or design |
| `status` | idea, planned, approved, building, review, blocked, parked or done |
| `owner_session` | a session name, or `none` (an empty or missing value counts as `none`, and lint flags it) |
| `owner_session_id`, `owner_session_pid` | the owner's session id and pid, `""` when unknown; optional, and a new owner name clears them |
| `rank` | one order per repo, lowest first, in steps of 10 |
| `depends_on` | the ids that must be finished first |
| `waiting_on` | what the doc waits on the owner for, else `""` |
| `issue`, `pr`, `branch` | a number, a URL or a name, else `none` |
| `fix_rounds` | the review fix rounds the piece has had; a doc without the key holds 0 |
| `updated` | the date of the last write, set by every write |

`kind` is the Conventional Commits type of the PR that ships the piece. A test-only fix is a bug, and a rename is a refactor.

The front matter is a strict subset of YAML: flat `key: value` lines, one-line `[a, b]` lists and double-quoted strings. A quoted string takes only the escapes `\"` and `\\`. Comments, blank lines, nested keys and single quotes are errors. A bare value that YAML reads as a bool, null, float or date (`yes`, `null`, `1.5`, `2026-11-05`) must be quoted. So must a value that holds `: ` or ` #`.

The body has five `##` sections: Goal, Decisions, Plan, Open questions and Owner checks. Open questions holds only `- [ ]` and `- [x]` items. An indented line continues the item above it.

## Code

`.local/bin/plans` is the entry point. It finds the library from its own real path and calls `cli.main()`. The library is the package in `.local/lib/plans/plans/`:

- `parse.py`: the front matter subset and the body sections, read into a `Doc`. `Doc.render` writes changes back line by line. Start here.
- `store.py`: the safe write path (`update`, `create`). Both the CLI and the board write only through it.
- `validate.py`: the lint rules and the old-layout detection.
- `query.py`: a repo's docs by glob (there is no index file), and the `ls`, `next`, `waiting` and `questions` queries.
- `roots.py`: the main checkout from a worktree or a submodule, and the repos for `--all`.
- `gh.py`: the `lint --gh` checks.
- `issues.py`: the issue check of `next`: the ranking rule, the GitHub calls and the cache.
- `cli.py`: argument parsing and output only.
- `server.py`: `plans serve`, the board's HTTP API, the mtime watcher and the event stream. `board.html` is the whole page, plain JavaScript with no build step.

`.config/systemd/user/plans-serve.service` runs `plans serve`. `plans` is stowed unfolded (see [stowing](../../lib/install/README.md#stowing)), so the unit links in beside the other packages' units.

`tests/` holds the unittest suite, which the `plans` check step runs (see [the check runner](../../lib/check/README.md)). `test_issues.py` drives the issue check with a stub `gh`. `test_store.py` races forked writers on one doc. `test_server.py` covers the board's reads, the watcher and shutdown, and `test_server_writes.py` its writes and conflicts.
