# plans

`plans` reads and edits the front matter of the plan docs under `.plans/`. Each doc is one piece of active work, at `.plans/<project>/<id>.md` in the main checkout of a repo. `plans` replaces the tracker files. The board in phase 2 imports the same library.

Stow the package with `just stow plans` (it is in the core list). The command lands in `~/.local/bin/plans`. It needs Python 3 and nothing else.

## Usage

Run `plans` anywhere in a repo or one of its worktrees. It always reads the main checkout, because worktrees do not see the git-ignored `.plans/`.

```bash
plans ls [--owner S] [--project P] [--status a,b] [--all] [--json]   # one line per doc
plans next [--as S] [--json]          # ask lines, blocked lines, then one work line
plans waiting [--all] [--json]        # docs with a non-empty waiting_on
plans questions [--all] [--json]      # the unchecked "- [ ]" items under Open questions
plans show <id> [--section NAME] [--json]
plans set <id> key=value...           # e.g. plans set demo status=building depends_on=a,b
plans claim <id> [--as S] [--force]   # owner_session = S
plans handoff --to T <id>... [--as S] [--force]
plans new <project> <id> [--kind K]   # writes .plans/<project>/<id>.md, kind feature by default
plans lint [--gh] [--all]
```

A line holds tab-separated columns: the repo (only with `--all`), id, status, owner, rank and waiting_on. `--json` prints the full front matter of each doc, plus its `path`.

`--all` reads every repo under the directories in `~/.config/plans/roots`, one per line. Without that file, the roots are `$GITHUB_DIR` (default `~/Development`) and the dotfiles checkout, found through the `~/.local/share/dotfiles/repos` link. A root that is a git repo counts as one repo. Any other root is searched three levels down, and the search stops at each repo it finds.

`--as` names the session, for example `dotfiles-56`. `$PLANS_SESSION` is the fallback. `claim` and `handoff` need one of the two.

- `next` walks the docs with status planned, approved or building, lowest rank first. It skips each doc that another session owns. Each doc above the first free doc gets a line. A doc that waits on the owner gets an `ask` line, and a doc with an unfinished dependency gets a `blocked` line. Then it prints one `work` line for the first free doc. A free doc has an empty `waiting_on` and no unfinished `depends_on` entry. A dependency is finished when its doc is done or gone, because a merged piece deletes its doc. A dependency whose doc cannot be read blocks, as `blocked by <id> (unreadable)`.
- `claim` and `handoff` refuse a doc that another session owns. `--force` overrides that. `handoff` checks every listed doc before it writes any of them.
- `set` refuses `id`, `project` and `updated`, a value with a line break, an unknown key, and a value outside a closed set. A list takes `a,b` or `[a, b]`.
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
| `rank` | one order per repo, lowest first, in steps of 10 |
| `depends_on` | the ids that must be finished first |
| `waiting_on` | what the doc waits on the owner for, else `""` |
| `issue`, `pr`, `branch` | a number, a URL or a name, else `none` |
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
- `cli.py`: argument parsing and output only.

`tests/` holds the unittest suite, which the `plans` check step runs (see [the check runner](../../lib/check/README.md)). `test_store.py` races forked writers on one doc.
