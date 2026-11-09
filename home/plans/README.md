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
plans note <id> --section NAME "text"  # append a bullet to a body section; Decisions bullets get today's date
plans claim <id> [--as S] [--force]   # owner_session = S
plans handoff --to T <id>... [--as S] [--force]
plans new <project> <id> [--kind K]   # writes .plans/<project>/<id>.md, kind feature by default
plans close <id> [--as S] [--force] [--dry-run]    # delete the doc and its log folder, drop it from depends_on
plans cancel <id> [--as S] [--force] [--dry-run]   # close, plus the PR, the issue and a clean worktree
plans lint [--gh] [--all]
plans reclaim                         # for a SessionStart hook: take back this session's docs
plans serve [--port N]                # the web board, see below
plans backup [--init]                 # restic snapshot of every repo's .plans/ and .logs/, see Backup
plans restore --list | <snapshot> [--repo R] [--apply]   # see Backup
```

A line holds tab-separated columns: the repo (only with `--all`), id, status, owner, rank and waiting_on. `--json` prints the full front matter of each doc, plus its `path`.

On `ls`, `waiting`, `questions` and `lint`, `--all` reads every repo under the directories in `~/.config/plans/roots`, one per line. Without that file, the roots are `$GITHUB_DIR` (default `~/Development`) and the dotfiles checkout, found through the `~/.local/share/dotfiles/repos` link. A root that is a git repo counts as one repo. Any other root is searched three levels down, and the search stops at each repo it finds.

`--as` names the session, for example `dotfiles-56`. `$PLANS_SESSION` is the fallback. `claim` and `handoff` need one of the two.

Two live sessions can get the same name, so a doc also records the owner's `$CLAUDE_CODE_SESSION_ID` and `$CLAUDE_PID` in `owner_session_id` and `owner_session_pid`. A session with the owner's name owns the doc when either value matches its own. The id changes on `/clear` and the pid on `--resume`. When both stored values differ, another session holds the name: `claim` and `handoff` refuse the doc, and `next` skips it. A `claim` writes the caller's values. A `set` refreshes both when either one matches the caller's. So a `/clear` and then a resume never lock the owner out while it writes in between. A shell without the two variables matches by name only and leaves the values as they are.

- `next` walks the docs with status planned, approved or building, lowest rank first. It skips each doc that another session owns. Each doc above the first free doc gets a line. A doc that waits on the owner gets an `ask` line, and a doc with an unfinished dependency gets a `blocked` line. Then it prints one `work` line for the first free doc. On `next`, `--all` does not scan other repos. It stays in the current repo and prints a `work` line for every free doc, in rank order, and a doc that depends on a free doc stays `blocked` until that doc is done. `--skip` leaves a doc out, for example one an agent already works on, but a skipped doc still blocks the docs that depend on it. A free doc has an empty `waiting_on` and no unfinished `depends_on` entry. A dependency is finished when its doc is done or gone, because a merged piece deletes its doc. A dependency whose doc cannot be read blocks, as `blocked by <id> (unreadable)`.
- `next` first prints an `ask` line for each open GitHub issue that no doc ranks, and one for each ranked issue that is closed. See [Issue ranks](#issue-ranks).
- A dead owner frees its doc. A doc whose `owner_session_pid` runs no Claude process (or no process at all; a `node` or `bun` that runs the `claude` launcher or a file of the `@anthropic-ai/claude-code` package counts as Claude, and so does a process whose executable path has a `claude` folder, such as `~/.local/share/claude/versions/<v>`) gets `owner_session: none`, with both values cleared, the moment any command reads it. The board checks each owner again every second, so it frees a doc even when no file changed. The CLI names each freed doc on stderr. A doc without a pid keeps its owner, and so does a pid whose `/proc` entry cannot be read. A re-claim that lands between the check and the write wins. The freed doc keeps the old owner in `last_owner_session` and `last_owner_session_id`, and any later write of `owner_session` clears both.
- `reclaim` is for a Claude Code SessionStart hook (`~/.claude/hooks/plans-reclaim.sh`, on startup, resume and clear). A resumed session keeps its session id but gets a new pid, and `/clear` keeps the pid but gives a new session id. `reclaim` reads the hook input on stdin and works in every repo under the roots, plus the current checkout. A doc whose `owner_session_id` is this session gets the new pid, and after a `/clear` only, a doc whose `owner_session_pid` is this session's pid gets the new id. On startup or resume that pid can be a dead owner's, reused after a reboot. A free doc whose `last_owner_session_id` is this session goes back to the last owner's name. A doc another session holds stays with it. The pid is the nearest Claude process above the hook, else `$CLAUDE_PID` when that runs Claude. `reclaim` prints nothing and always exits 0.
- `claim` and `handoff` refuse a doc that another session owns. `--force` overrides that. A forced `claim` writes the caller's values. `handoff` checks every listed doc before it writes any of them. Every `handoff` clears both values, forced or not, and the receiver's first `claim` writes its own.
- `close` is the cleanup after a merge. It drops the id from every other doc's `depends_on`, deletes `.logs/<project>/<id>/`, then deletes the doc. The doc goes last, so a failed step leaves it for a retry. It makes no GitHub or git change. Nothing archives the doc: git ignores it, and the issue keeps the record.
- `cancel` drops a card you no longer want. In order, it closes the doc's PR unmerged with a comment (only if open), closes the issue as not planned (only if open, and not when another doc names the same issue), removes the worktree that has the doc's branch checked out (only if it has no uncommitted changes, and never the main checkout), then runs the `close` cleanup. The branch stays, local and remote, so the PR can be reopened. A step that fails stops the run. The doc stays, and the output says what is `done`, `skipped`, `failed` and `not run`. A dirty worktree is `skipped`, and the run goes on.
- `close` and `cancel` refuse a doc that another session owns, as `claim` does, and a caller without a session name owns nothing. `--force` overrides that. `--dry-run` prints each `would:` line and changes nothing. They delete only the doc file and its own log folder, and refuse an id or project that is not a plain name. A `pr` or `issue` value that is no number or GitHub URL, and a branch that is no branch name, are refused.
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

Every open GitHub issue of a repo needs a rank. A doc ranks an issue when its `issue` key holds the number (`12`, `#12` or the issue URL), or its `## Plan` section names it as `#12`. Other sections hold history, so `#12` there does not count, and neither does `other/repo#12`. An issue that no doc covers gets its own doc, with `issue` set, status `parked` and a `- #12 title` line in its Plan. Its rank is its place in the order. No shared doc holds such issues.

`plans next` prints the gaps before its other lines:

```
ask	#1465	rank: plain-writing lint: rare shell forms still hide or invent PR bodies
ask	#94	closed: drop it from cursor-drag-reenter
```

A `rank` line is an open issue that no doc ranks. A `closed` line names the first doc by rank that still ranks a closed issue. With `--json`, these rows carry `"issue": N`, and `path` is the doc, or null. The check only reports. It never edits a doc.

The repo comes from the `origin` remote, so a repo without a GitHub origin gets no check and no network call. The answers from `gh` are cached in `$XDG_CACHE_HOME/plans/<owner>/<repo>.json` (default `~/.cache`, readable by you only) for 10 minutes, and a ranked number the cache does not know fetches again. Each `gh` call gets 5 seconds. When `gh` is missing or fails, `next` uses the old cache, and without one it prints no issue lines. After a failure, `next` waits a minute before it asks `gh` again, so an offline `next` pays the timeout once. Delete the file to fetch at once.

## Serve

`plans serve` runs a web board over the docs of every repo under the roots, the same repos as `--all`. Open http://127.0.0.1:8765 in a browser. It needs nothing beyond Python 3.

In Hyprland, `SUPER + A`, then `K` opens the board, starting the service first when the port is closed. With `remote.json` set and the tailnet address answering, it opens that address instead of 127.0.0.1. The tailnet address refuses `e` (open in editor) and `x` (cancel), so for those open http://127.0.0.1:8765 instead.

To run it in the background with every graphical session, enable the user service. `just stow plans` installs it, but nothing enables it:

```bash
systemctl --user enable --now plans-serve
```

The service is wanted by `graphical-session.target`, so it starts and stops with that target. A text-only or SSH login does not start it.

The service does not see a `GITHUB_DIR` that only the shell exports. Without the roots file (`~/.config/plans/roots`, one directory per line) it uses the default roots and can miss repos that `plans ls --all` finds. The file replaces the defaults, so list every root in it, including the dotfiles checkout.

The board has a column per status and a lane per repo, then per project. The header holds a repo search box and filters for the owner, project, status, kind and waiting on the owner. A card shows the id, kind, owner, rank, `waiting_on`, the PR link and a badge per `depends_on` entry. A doc outside the front matter subset shows as a red error card. The board refreshes within a second when an agent changes a doc, and it finds a new repo within 30 seconds.

| Key | Action |
| --- | --- |
| `j` `k` | the next or previous card in the column; a move onto or past the first or last card scrolls to the very top or bottom, unless that hides the card, then it scrolls just far enough to show it |
| `gg` `G` | the first or last card in the column, and scroll to the very top or bottom (just far enough to show the card if it lies elsewhere); with no card selected, the first card of the first column that has cards (a lone `g` does nothing) |
| `h` `l` | the nearest card in the column to the left or right |
| `H` `L` | move the card one status column; a move to blocked or done asks `y` / `n` |
| `J` `K` | move the card one place down or up in its cell (its rank) |
| `o`, Enter | open the doc view of the card; Esc closes it |
| double-click a card | the same as `o` (not on the owner badge or a link) |
| `e` | open the doc in `$EDITOR` in a new terminal |
| `a` | edit the owner: a session name or `none` |
| `x` | cancel the card: the prompt lists every change (PR, issue, worktree, files) and `y` runs it. A card that a session owns is refused: set the owner to none with `a` first. There is no board key for `close` |
| `/` | the repo search box |

The doc view is a side panel on the right. It shows the rendered doc and the phone sheet's status buttons, rank buttons and owner field. The board stays in view, and the panel follows the selection as the keys move it. Every key above works with the panel open. The doc is read-only: `e` opens the editor. An unreadable doc shows its error and its raw text. The renderer covers the markdown that plan docs use: headings, nested lists, `- [ ]` items, code, bold, italic, http(s) links and `#12` issue links. It folds the front matter into one "Fields" line that opens on a click, and shows anything else as plain text. The doc text is escaped before any markup goes in, so HTML in a doc shows as text.

The repo search box lists the repos that have plan docs, with all repos first. Typing keeps the repos whose `owner/name` label or folder name holds the letters in order, best match first, and a hit at a word start or in a run ranks higher. Arrow keys move the highlight, Enter or a click picks, Esc closes the list, and Tab leaves without a pick. Pick all repos, or empty the box and press Esc, to clear the filter. The pick does not survive a page reload. The matcher has a node test: `node home/plans/tests/fuzzy.test.mjs`. `tests/test_board_fuzzy.py` runs it in the `plans` check step.

A drag moves a card within its lane, to another status, another place or both. A drop takes the midpoint of the ranks around it. When there is no gap, the board renumbers the repo in steps of 10.

Each write goes through the same safe write path as `plans set`, and the board compares against the values it showed. If an agent changed one of those keys since the board last loaded, the write is refused. The card snaps back and a message names the keys. A renumber skips a doc that an agent re-ranked meanwhile, keeps the agent's rank and says which doc it skipped. Status and owner follow the rules of `plans set`. The other keys are read-only on the board.

`e` uses the terminal launcher that the Hyprland config writes (`~/.local/state/hypr/bin/term`), else `$TERMINAL`. The editor is `$VISUAL`, then `$EDITOR`, then `nvim`. The user service does not see the shell's `$EDITOR`; if it should differ, run `systemctl --user set-environment EDITOR=...`, then `systemctl --user restart plans-serve`, because the setting reaches only processes that start later. `VISUAL` wins over `EDITOR`, so set `VISUAL` instead if the manager already has one.

The board listens on 127.0.0.1 only and has no login. It refuses a request whose Host header is not `127.0.0.1` or `localhost` on its port, unless `remote.json` opens the phone host (see [On the phone](#on-the-phone)). A write also needs the board's own request header, so a page on another site cannot write.

### On the phone

The board opens on a phone over Tailscale. `tailscale serve` takes HTTPS on the laptop's MagicDNS name and passes each request to the board on 127.0.0.1. Setup, once:

1. In the [Tailscale admin console](https://login.tailscale.com/admin/dns), turn on MagicDNS and HTTPS certificates.
2. Write `~/.config/plans/remote.json` with the laptop's MagicDNS name and your tailnet login. `tailscale status --json` shows both, under `Self.DNSName` and `User.<id>.LoginName`:

   ```json
   {"host": "laptop.tail1234.ts.net", "login": "you@github"}
   ```

3. Restart the board: `systemctl --user restart plans-serve`. It reads the file at start and prints the phone address.
4. Run `tailscale serve --bg --https=443 http://127.0.0.1:8765`. The setting survives reboots. `tailscale serve reset` removes it.
5. Open `https://<host>` on the phone, with Tailscale on.

Without `remote.json` the board answers on 127.0.0.1 and `localhost` only, as before. A broken file keeps it that way and says so in the journal.

The board serves the phone host only when the request carries a `Tailscale-User-Login` header equal to `login`. `tailscale serve` sets that header itself and drops any copy the client sent, and it sends none for a tagged device or a Funnel request. So another tailnet user, a shared device or the open internet gets a 403. The board still listens on 127.0.0.1 only, so nothing but `tailscale serve` and local programs reach it. A local program can send any header, as it can already use the board today. A write from the phone needs the same board header, with the phone page's own origin.

Below 600 pixels wide, the board shows one status at a time. A tab per status holds a count, and a sideways swipe moves to the next or previous tab. It opens on building. A tap on a card opens a sheet with the status buttons, rank up and down, the owner field, and the rendered doc, read-only. Each button writes through the same path as the desktop keys, with the same refusals and the same question before blocked or done. The phone has no cancel and no editor, and the server refuses both from the phone host.

## Backup

`.plans/` and `.logs/` are git-ignored, so git holds no copy. `plans backup` snapshots both folders of every repo under the roots (the same repos as `--all`) with restic, encrypted, into the rclone remote `gdrive:backups/plans`. After each snapshot it prunes with keep-hourly 48 and keep-daily 30. Set `PLANS_BACKUP_REPO` or `PLANS_BACKUP_PASSWORD_FILE` to use another restic repo or password file.

One-time setup:

1. `rclone config`: make a Google Drive remote named `gdrive`.
2. `plans backup --init`: writes a random password to `~/.config/plans/backup-password` (mode 600, never tracked) and creates the restic repo. It never overwrites an existing password file.
3. Copy that password into the password manager. Without it the backups cannot be read.
4. `systemctl --user enable --now plans-backup.timer`. `just stow plans` installs the units, but nothing enables them. The timer runs `plans-backup.service` hourly and catches up after a missed run (`Persistent=true`). The service reads the roots like the board service does, so list every root in `~/.config/plans/roots`.

A failed run sends a desktop notification and exits 1. A run that exceeds 30 minutes is killed by systemd, and `plans-backup-notify.service` (via `OnFailure=`) sends the notification instead. Restic exit 3 (some files unreadable, snapshot made) is a warning, not a failure. `journalctl --user -u plans-backup` has the restic error.

Restore, for example on a new machine after you clone the repos:

```bash
plans restore --list                         # snapshot id, time, host, repo count
plans restore latest                         # dry run: restores to a temp folder, lists new and differing files
plans restore latest --repo dotfiles         # only one repo: a path under the roots, or its folder name
plans restore latest --apply                 # copy the restored files into place
```

Without `--apply` nothing changes. `--apply` overwrites differing files and adds missing ones, and it never deletes a file the snapshot lacks. It skips and reports (exit 1) a snapshot repo that is not under the roots or not cloned here, and refuses a `--repo` path outside the roots. It never writes outside a repo's `.plans/` or `.logs/`, even through a symlink.

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
| `last_owner_session`, `last_owner_session_id` | the dead owner that a release freed the doc from, `""` once anyone writes `owner_session`; optional |
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
- `validate.py`: the lint rules, the old-layout detection and the finding for each Syncthing conflict copy.
- `query.py`: a repo's docs by glob (there is no index file; a `*.sync-conflict-*` copy is no doc, and `conflict_paths` lists the copies), and the `ls`, `next`, `waiting` and `questions` queries.
- `roots.py`: the main checkout from a worktree or a submodule, and the repos for `--all`.
- `backup.py`: `plans backup` and `plans restore`: the restic calls, the path selection from `roots.py`, the restore diff and the guarded copy.
- `gh.py`: the `lint --gh` checks, and the `gh` runner.
- `retire.py`: `close` and `cancel`: the step list (the dry run and the board's prompt) and the ordered apply.
- `issues.py`: the issue check of `next`: the ranking rule, the GitHub calls and the cache.
- `liveness.py`: the dead-owner check on the stored pid, the release write every read runs, and the take-back that `reclaim` runs.
- `cli.py`: argument parsing and output only.
- `server.py`: `plans serve`, the board's HTTP API, the mtime watcher and the event stream, and the phone check (`remote.json`, `Handler.is_remote`). `board.html` is the whole page, plain JavaScript with no build step. Its phone layout starts at `render_phone`, and the sheet there is also the desktop doc view. The markdown renderer sits between the `markdown:start` and `markdown:end` markers.

`.config/systemd/user/plans-serve.service` runs `plans serve`. `plans` is stowed unfolded (see [stowing](../../lib/install/README.md#stowing)), so the unit links in beside the other packages' units.
`.config/systemd/user/plans-backup.service` and `plans-backup.timer` run `plans backup` hourly, and `plans-backup-notify.service` notifies when systemd kills a run. `test_backup.py` drives backup and restore with a stub `restic` on PATH.

`tests/` holds the unittest suite, which the `plans` check step runs (see [the check runner](../../lib/check/README.md)). `test_issues.py` drives the issue check with a stub `gh`. `test_store.py` races forked writers on one doc. `test_liveness.py` judges processes it spawns and a fake `/proc`, which the other tests use too. `markdown.test.mjs` feeds the renderer hostile and random docs and checks that only its own tags come out, and `test_board_markdown.py` runs it, as `test_board_fuzzy.py` runs `fuzzy.test.mjs`. `test_server.py` covers the board's reads, the phone host and login check, the doc text, the watcher and shutdown, and `test_server_writes.py` its writes and conflicts, from the laptop and the phone. `test_retire.py` drives `close` and `cancel` with a fake `gh` and a `git` wrapper on PATH, so no test reaches GitHub or a real repo.
