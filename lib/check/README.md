# The check runner

`lib/check.sh` is a shim for `lib/check/runner.py`; it works as `sh lib/check.sh` and as `lib/check.sh`. The step table, the path rules and the shell file groups are in `lib/check/scopes.py`, where a new step goes. This file holds what the shim's header used to: the options, the environment, the step list and how passes are recorded. Editing the shim is scope "all" (every step reruns, about 4 minutes); editing this file reaches only `check-scope` and `check-cache`.

## Running it

```
lib/check.sh                  every step
lib/check.sh --changed <base> only the steps the files changed since <base> can affect
lib/check.sh --paths-from <file|-> like --changed, but the changed paths are the lines of the file (or stdin), relative to the
                              repository root, instead of `git diff <base>`: a commit's staged paths, say
lib/check.sh --only <step>[,<step>...] only the named steps (repeatable), whatever their scope; with --changed or
                              --paths-from, those of them the change reaches. An unknown name exits 2 before anything runs
lib/check.sh --plan [--changed <base>|--paths-from <file|->] [--only ...] prints the plan (the summary line, then each shellcheck list) and exits 0, running nothing
```

`--changed` always runs the "tree" steps: `git-diff-check`, `whitespace`, `conflicts`, `symlinks`, `packages`, `ignored-integrations`, `qml-ipc` and `readme-links`. A change to `lib/check.sh`, the runner's own modules (`runner.py`, `keys.py`, `scopes.py`, `lock.sh`, `passed.sh`, `passed.py`), the `justfile`, `.claude/check-commands` or any path no rule in `scopes.py` claims runs everything.

The parallel output of a step is buffered and a passing step prints one line; after the `FAILED:` line, the last 25 lines of each failing step follow. A step whose tool is missing prints `skip:` and passes. Run a suite through `--only` rather than by hand (a hook warns), so its pass is recorded and the final `--changed` run does not repeat it.

### Reading the summary

- `skipped (passed for these inputs)`: the step was not run because a recorded pass has the same key (below). It passed earlier; it was not left out.
- `skipped by scope`: no changed path reaches the step.
- `skipped by request`: named in `CHECK_SKIP_STEPS`.
- `skip: <reason>`: a tool the step needs is missing; the step counts as passing and no pass is recorded.

### Environment

- `CHECK_FULL=1` makes `--changed` run everything, and runs every step whatever passed before. `.claude/hooks/guard-check-full.sh` denies it when the tree already has a recorded pass, unless `CHECK_FULL_REASON` is set.
- `CHECK_JOBS` sets how many steps run at once (default half the cores, always clamped to 1-4); 1 runs them one after another with live output.
- `CHECK_SKIP_STEPS="step ..."` drops those steps whatever the scope says (the summary line lists them).
- `CHECK_HEAVY_SLOTS` (default 1) and `CHECK_LOCK_WAIT_SECS` (default 1200): see "Slots". `CHECK_NO_LOCK=1` runs the heavy steps without a slot, for a check that must never wait.
- Everything runs at nice 19 in the idle IO class.

### Where it runs on its own

Nothing runs it at the end of a turn. A commit runs it (`.claude/hooks/check-before-commit.sh`: `--paths-from` the committed files, `CHECK_NO_LOCK=1`, without the five voxcmd suites). A PR open only looks up a recorded pass (`.claude/hooks/check-before-pr.sh`). ship-batch runs it on each PR's branch, then on main. A worktree has no `repos/`, so its pass does not cover `symlinks` for the main checkout: run the check in the real checkout before merging.

## Steps

The "needs" tools are optional unless stated. Each step's command and scope is in `scopes.py`.

- `shellcheck`, `shfmt`: the installer, `lib/` (common, install, check), `demo/`, `home/voxcmd/tests/`, `home/calendar/tests/`, the Quickshell audio importers (`scripts/lib/*.sh`, `ff7-`, `goldeneye-`, `mgs2-`, `ocarina-audio`) and the tracked agent scripts under `.claude/` and `home/claude/.claude/` (by `*.sh` name or shell shebang; not `worktrees/` or `skills/synced/`); shfmt uses `-i 2`. Need shellcheck, shfmt.
- `stylua`, `luacheck`: Hyprland config (stylua) and Hyprland plus greetd Lua (luacheck, via `lib/check/steps/lua.sh`). Need stylua; luacheck or lua5.4/5.3/luajit with LuaFileSystem.
- `qmllint`: Quickshell config and greeter (`lib/check/steps/qml.py`). Needs Qt 6 qmllint.
- `qml-paths`: file paths built as strings in Quickshell QML and JS exist: `Qt.resolvedUrl`, `shellDir`, QML and JS imports, in the shell and in the greeter tree (`lib/common/greeter-files.sh`), and the files outside Quickshell that name a path in it (`lib/check/steps/qml_paths.py`).
- `qml-layers`: no Quickshell import or literal URL load runs to a higher layer than its file's, except the edges in `lib/check/qml-layers.allow`, which fails when one goes stale (`lib/check/steps/qml_layers.py`).
- `qml-singleton-names`: no Quickshell `pragma Singleton` file is named `*Config`, `*Store` or `*Manager`, except the temporary lines in `lib/check/qml-singleton-names.allow`, which fails when one goes stale (`lib/check/steps/qml_singleton_names.py`).
- `qml-ipc`: every `qs ipc call` target and function in scripts, Lua, Rust, `tmux.conf` and test stubs is a typed function of an IpcHandler, and every handler is called, except `lib/check/qml-ipc.allow`, which fails when a line goes stale (`lib/check/steps/qml_ipc.py`). It also checks the README IPC table: a row per handler, and only real functions in a row. Always runs.
- `readme-links`: every link and backticked repo path in the Quickshell READMEs exists, and every `#anchor` names a heading (`lib/check/steps/readme_links.py`). Always runs. It reads only the Quickshell tree, so this file's links are not checked by it.
- `lock-skins`: `features/lock/skins/index.json` matches the skin files and audio importers (`lib/check/steps/lock-skins.sh`). Needs jq.
- `style-exports`: generated property lines in `theme/Style.qml` match `theme/StyleSchema.js` (`lib/check/steps/style-exports.sh`). Needs python3.
- `time-format`: no hand-built am/pm text in Quickshell QML/JS; clock text goes through `TimeFormat` (`lib/check/steps/time-format.sh`).
- `shaders`: each tracked Quickshell `.frag` rebuilds (qsb) to its committed `.frag.qsb` byte for byte, and its `// Rebuild:` header matches the command used; `just shaders` rewrites them (`lib/check/steps/shaders.sh`). Needs qsb (qt6-shadertools).
- `json-store`: `home/quickshell/tests/json_store/run.sh`, the lifecycle tests of `core/JsonStore.qml` in a headless qs. Needs qs, python3.
- `voxcmd-phrases`: each phrase in `home/voxcmd/tests/phrases.tsv` routes as recorded (`run-phrases.sh`). Needs jq, fzf.
- `voxcmd-click`: voxcmd's click support (`run.sh`, with `run-sessions.sh`, `run-modes.sh`, `run-sequences.sh`, `run-overview.sh` and `run-monitors.sh` beside it). Needs jq, fzf.
- `voxcmd-calendar`: the calendar phrases against stubs (`run-calendar.sh`). Needs jq, fzf.
- `voxcmd-wake`: the wake word listener (`run-wake.sh`). Needs jq, fzf.
- `voxcmd-firefox`: the Firefox extension and its native-messaging host (`run-firefox-extension.sh`). Needs jq, fzf; the extension's script runs under node when present.
- `voxtype-duck`: `home/voxtype/tests/run-duck.sh`, the output-sink ducker. Needs python3.
- Voxcmd suite scopes: each of the five bash voxcmd suites has its own scope (`voxphrases`, `voxclick`, `voxcalendar`, `voxwake`, `voxfirefox`), so an edit to a file only one suite reads runs only that suite. The bash voxcmd itself, its integrations, voxtype-daemon and `extras/voxcmd-firefox` reach all five. A file under `home/voxcmd/tests` gets its row in `PATH_SCOPES` naming the suites that read it, and a fixture with no row of its own falls to the `home/voxcmd/*` catch-all, which `lib/check/tests/test_voxcmd_suite_scopes.py` rejects; add the row when you add a fixture.
- `voxcmd-rust`: the voxcmd crate: `cargo fmt --check`, clippy `-D warnings`, `cargo test` (`lib/check/steps/voxcmd-rust.sh`). Takes no heavy slot and runs in the ordinary pool, not the serial lane. Needs cargo.
- `calendar-sync`: `home/calendar/tests/run.sh`. Runs only when python-icalendar and python-recurring-ical-events import.
- `calendar-sync-syntax`: the syntax check of `calendar-sync`; always runs when its scope is reached, whatever the libraries.
- `firefox-policy`: `lib/install/tests/firefox-policy.sh`, the Firefox policy installer. Needs jq.
- `greeter-keyring`: `lib/install/tests/greeter-keyring.sh` (the greetd keyring unlock installer), `greeter-log.sh` (the greeter log file and the `qs-greeter` wrapper's choice of it) and `greeter-monitors.sh` (the greeter's `monitors.lua`).
- `migrate-lock`: the `migrate-quickshell-*` and `migrate-lock-assets` tests in `lib/install/tests/`.
- `install-load`: `lib/install/tests/load.sh`, that sourcing the install libraries prints nothing and never exits.
- `agent-hooks`: the tests of `guard-masked-checks.sh`, `check-before-pr.sh`, `restart-qs-after-git.sh`, `guard-gh-merge.sh`, `warn-direct-voxcmd-suite.sh`, `guard-tmux-socket.sh`, `guard-check-full.sh`, `context-budget.sh` and `report-failed-main-check.sh`. Needs jq.
- `stale-shells-hook`: the test of `stale-shells.sh`. Needs jq.
- `owner-test-bar`: the owner-test-bar skill's `tests/run.sh`, when it changes. Needs jq.
- `ship-batch`, `merge-prs`: those skills' `tests/run.sh`, when either changes.
- `notification-markup`: `home/quickshell/tests/notification_markup.js`, the notification body sanitizer. Needs node.
- `check-scope`, `check-cache`: which steps `--changed` picks (`lib/check/tests/scope.sh`), and the runner's scopes, keys, pass records and slot lock (`lib/check/tests/test_*.py`, `cache.sh`, `lock.sh`), and `shaders.sh`, the shaders step's tests. Any file under `lib/check/` reaches them, this README included.
- `packages`: duplicate package names across the manifests (`lib/check/steps/packages.sh`).
- `symlinks`, `whitespace`, `conflicts`, `git-diff-check`: tracked symlinks that dangle or leave the repo; trailing whitespace; conflict markers; and `git diff --check HEAD`.
- `ignored-integrations`: no voxcmd integration or replacement file is one git ignores (`lib/check/steps/ignored-integrations.sh`).

## Passes

A step that passes is recorded (`lib/check/passed.sh`) under a key hashing the step's definition (command, scope, needs, probe) and the content of the files it reads, the same files whose change makes `--changed` pick it (its scope in `scopes.py`). `scopes.py` itself is no input of other steps' keys, so editing it reruns only the steps it changes. A later run skips a step whose key already passed, uncommitted and untracked content included, and a pass is recorded only when the step's files did not change while it ran. The records are in the repository's common git dir, shared by every worktree.

A run that leaves the tree clean also records the tree: when every step passed for its content, or for `--changed <base>` on top of a base recorded as passed. A `--changed` run records that it passed against `<base>`, which is what the PR hook looks up. An `--only` run records its steps' passes, under the same keys a later `--changed` run looks up, but never the tree or a base. The shell steps (`shellcheck`, `shfmt`) key on the run's file lists, so for them pass `--only` the same `--changed` base the final run will use, or expect it to run them again. With `VOXCMD_ONLY_SECTIONS` set the voxcmd suites run in part, so no run records their pass, the tree or a base.

## Slots

At most `CHECK_HEAVY_SLOTS` heavy steps run at once on the machine, each holding a flock'd slot (`lib/check/lock.sh`) and waiting at most `CHECK_LOCK_WAIT_SECS` for one. The heavy steps are the five voxcmd suites and `voxtype-duck`; every other step, `voxcmd-rust` included, takes none. The five voxcmd suites also run one after another in a lane of their own, ahead of the rest, because they are timing-sensitive; `voxtype-duck` takes a slot but runs in the ordinary pool. On INT or TERM the running steps and their children are ended.
