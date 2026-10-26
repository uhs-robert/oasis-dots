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

`--changed` always runs the "tree" steps: `git-diff-check`, `whitespace`, `conflicts`, `symlinks`, `packages`, `ignored-integrations`, `qml-ipc`, `readme-links`, `specs` and `registry`. A change to `lib/check.sh`, the runner's own modules (`runner.py`, `keys.py`, `scopes.py`, `lock.sh`, `passed.sh`, `passed.py`), the `justfile`, `.claude/check-commands` or any path no rule in `scopes.py` claims runs everything.

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
- `qml-layers`: no Quickshell import or literal URL load runs to a higher layer than its file's, except the edges in `lib/check/qml-layers.allow`, which fails when one goes stale. Two more rules, with their exceptions in `SIBLING_ALLOW` in `lib/check/steps/qml_layers.py`:
  - no relative import runs from one feature (or style) into a sibling;
  - no relative `.js` import reaches a sibling folder of its layer: own, lower and ancestor folders and lower layers pass, and so does any folder of `ui/` from `ui/`.
- `qml-singleton-names`: no Quickshell `pragma Singleton` file is named `*Config`, `*Store` or `*Manager`, except the temporary lines in `lib/check/qml-singleton-names.allow`, which fails when one goes stale (`lib/check/steps/qml_singleton_names.py`).
- `qml-ipc`: every `qs ipc call` target and function in scripts, Lua, Rust, `tmux.conf` and test stubs is a typed function of an IpcHandler, and every handler is called, except `lib/check/qml-ipc.allow`, which fails when a line goes stale (`lib/check/steps/qml_ipc.py`). It also checks the README IPC table: a row per handler, and only real functions in a row. Always runs.
- `readme-links`: every link and backticked repo path in the Quickshell READMEs, `docs/` and `specs/` exists, and every `#anchor` names a heading (`lib/check/steps/readme_links.py`). Always runs. `specs/roadmap.md` is held to its links only, since it names files not yet written. This file is not read.
- `specs`: front matter of `specs/core/*.md` (TEMPLATE.md included) validates against `specs/schema/spec.yaml`, each spec's id is its file name, it has its title and headings, and its requirement ids carry the id in capitals as prefix and are unique; each id is tagged `req: BAR-03` in a test under `lib/check/tests`, `home/voxcmd/tests`, `home/quickshell/tests`, `home/hypr/tests`, `home/calendar/tests`, `home/voxtype/tests` or `.claude/skills/shadow` (in a `.tsv` row, in its note column: the one the header names `note`, else the fourth) or marked `[gap: untested]`/`[gap: unmet]`, a tag naming no requirement fails, untagged test files are listed as info only, and `specs/gaps.md` must equal what the markers generate (`lib/check/steps/specs.py --write` regenerates it); front matter of `.plans/**/*.md` against `specs/schema/plan.yaml`. `.plans/` is local, so the plan schema runs only on a checkout that has it (the main one), and its unit tests carry the plan cases. Always runs, since an edit of an ignored plan file reaches no path rule. A pass is keyed on the content of the ignored `.plans/` files too. Fails, not skips, without check-jsonschema (`packages/pipx.ini`) (`lib/check/steps/specs.py`).
- `registry`: the action definitions refer to things that exist. `home/hypr/tests/act_refs.lua` loads every `lib/actions/defs/*.lua` headlessly and prints the action list; the step reads it in memory and discards it (no list is committed). It fails on an `Act` warning (unknown id, duplicate, bad params, undeclared `{param}`), a malformed or repeated id, an `ipc` action naming a function that is not a typed IpcHandler function (read by `qml_ipc.declared`) and a `command` action whose `~/` program no `home/<package>/` ships (`lib/check/steps/registry.py`). Always runs. Skips without lua.
- `lock-skins`: `features/lock/skins/index.json` matches the skin files and audio importers (`lib/check/steps/lock-skins.sh`). Needs jq.
- `style-exports`: generated property lines in `theme/Style.qml` match `theme/StyleSchema.js` (`lib/check/steps/style-exports.sh`). Needs python3.
- `time-format`: no hand-built am/pm text in Quickshell QML/JS; clock text goes through `TimeFormat` (`lib/check/steps/time-format.sh`).
- `shaders`: each tracked Quickshell `.frag` rebuilds (qsb) to its committed `.frag.qsb` byte for byte, and its `// Rebuild:` header matches the command used; `just shaders` rewrites them (`lib/check/steps/shaders.sh`). Needs qsb (qt6-shadertools).
- `json-store`: `home/quickshell/tests/json_store/run.sh`, the lifecycle tests of `core/JsonStore.qml` in a headless qs. Needs qs, python3.
- `polled-command`: `home/quickshell/tests/polled_command/run.sh`, pins that Quickshell ends a Process's stdout at the exit even when a child holds the pipe, which `core/PolledCommand.qml` relies on. Its own scope `polledcmd` covers that component and `tests/polled_command/`. Needs qs, python3.
- `polled-file`: `home/quickshell/tests/polled_file/run.sh`, the read, failure, path-change, gating and interval tests of `core/PolledFile.qml` in a headless qs. Its own scope `polledfile` covers that component and `tests/polled_file/`. Needs qs, python3.
- `colors-preview`: `home/quickshell/tests/colors_preview/run.sh`, which opens the Palette list in a tall Colors pane at four widths in a headless qs and fails if the list and the preview card intersect (#1293). Its own scope `colorsprev` covers `RowsSection.qml`, `ColorsSection.qml` and `tests/colors_preview/`. Needs qs.
- `restarting-stream`: `home/quickshell/tests/restarting_stream/run.sh`, the lifecycle tests of `core/RestartingStream.qml` (planned exits, re-probing, `wanted` during backoff) in a headless qs. Its own scope `restartstream` covers that component and `tests/restarting_stream/`. Needs qs, python3.
- `voxcmd-phrases`: each phrase in `home/voxcmd/tests/phrases.tsv` routes as recorded (`run-phrases.sh`). Needs jq, fzf.
- `voxcmd-click`: voxcmd's click support (`run.sh`, with `run-sessions.sh`, `run-modes.sh`, `run-sequences.sh`, `run-overview.sh` and `run-monitors.sh` beside it). Needs jq, fzf.
- `voxcmd-calendar`: the calendar phrases against stubs (`run-calendar.sh`). Needs jq, fzf.
- `voxcmd-wake`: the wake word listener (`run-wake.sh`). Needs jq, fzf.
- `voxcmd-firefox`: the Firefox extension and its native-messaging host (`run-firefox-extension.sh`). Needs jq, fzf; the extension's script runs under node when present.
- `voxtype-duck`: `home/voxtype/tests/run-duck.sh`, the output-sink ducker. Needs python3.
- Voxcmd suite scopes: each of the five voxcmd shell suites has its own scope (`voxphrases`, `voxclick`, `voxcalendar`, `voxwake`, `voxfirefox`), so an edit to a file only one suite reads runs only that suite. The crate's sources, the integrations, voxtype-daemon and `extras/voxcmd-firefox` reach all five. A file under `home/voxcmd/tests` gets its row in `PATH_SCOPES` naming the suites that read it, and a fixture with no row of its own falls to the `home/voxcmd/*` catch-all, which `lib/check/tests/test_voxcmd_suite_scopes.py` rejects; add the row when you add a fixture.
- `voxcmd-rust`: the voxcmd crate: `cargo fmt --check`, clippy `-D warnings`, `cargo test` (`lib/check/steps/voxcmd-rust.sh`). Takes no heavy slot and runs in the ordinary pool, not the serial lane. Needs cargo.
- `calendar-sync`: `home/calendar/tests/run.sh`. Runs only when python-icalendar and python-recurring-ical-events import.
- `calendar-sync-syntax`: the syntax check of `calendar-sync`; always runs when its scope is reached, whatever the libraries.
- `firefox-policy`: `lib/install/tests/firefox-policy.sh`, the Firefox policy installer, and `voxcmd-install.sh`, `install_voxcmd`. Needs jq.
- `pacman-tweaks`: `lib/install/tests/pacman-tweaks.sh`, the pacman and makepkg tuning (`lib/install/pacman.sh`, `system/etc/makepkg.conf.d/`).
- `greeter-keyring`: `lib/install/tests/greeter-keyring.sh` (the greetd keyring unlock installer), `greeter-log.sh` (the greeter log file and the `qs-greeter` wrapper's choice of it) and `greeter-monitors.sh` (the greeter's `monitors.lua`).
- `migrate-lock`: the `migrate-quickshell-*` and `migrate-lock-assets` tests in `lib/install/tests/`.
- `install-load`: `lib/install/tests/load.sh`, that sourcing the install libraries prints nothing and never exits.
- `agent-hooks`: the tests of `guard-masked-checks.sh`, `check-before-pr.sh`, `restart-qs-after-git.sh`, `guard-gh-merge.sh`, `warn-direct-voxcmd-suite.sh`, `guard-tmux-socket.sh`, `guard-check-full.sh`, `context-budget.sh`, `orchestrator-window-names.sh` (a private tmux server) and `report-failed-main-check.sh`. Needs jq, tmux and flock.
- `stale-shells-hook`: the test of `stale-shells.sh`. Needs jq.
- `owner-test-bar`: the owner-test-bar skill's `tests/run.sh`, when it changes. Needs jq.
- `ship-batch`, `merge-prs`: those skills' `tests/run.sh`, when either changes.
- `frame-lone-flush`: `home/hypr/tests/frame_lone_flush.lua` runs `config/general/frame.lua` against a stubbed `hl` and checks the lone-window flush opt-out (when it starts and ends) and the workspace animation swap. Needs lua.
- `bind-action`: `home/hypr/tests/bind_action.lua` runs `lib/actions/defs/tools.lua` against a stubbed `hl`: the 14 tool actions register the keys, extra keys, labels and `submap_universal` flags written out in the test with no warning, perform the command written out in the test through `Ipc`/`Cmd` argv, and their binds can be unbound. Needs lua.
- `act-lib`: `home/hypr/tests/act.lua` runs `lib/act.lua` against a stubbed `hl`: `Act.define`/`bind` register keys (`bind`'s `desc` replaces the label on one key or, as `false`, hides it) and skip bad definitions with a warning, `run`/`run_cli` check and coerce typed params, `Ipc`/`Cmd` carry their data and render `{param}` in one pass, and hostile strings (quotes, `]]`, newlines, `{param}`, leading `-`) round-trip through `sh` and a Lua long-string chunk. `Act.list_json` and `write_list` produce the list `hypr-act list` prints. Needs lua.
- `act-global`: `home/hypr/tests/act-global.sh` runs `act_global.lua` against a stubbed `hl` and the keymaps `keymaps/global/{general,workspace,media,mouse}.lua` under four Config shapes (vim keys or arrows, global or persistent workspaces, monitor counts, with and without a leader): every registered bind must match `home/hypr/tests/fixtures/act_global_binds.tsv` (key, which-key label, flags, what it dispatches), the action ids must exist, and the workspace ids must follow `Config.persistent_workspaces` at run time. The repo's `git status` must be unchanged afterwards. Needs lua.
- `hypr-act`: `home/hypr/tests/hypr-act.sh` runs `home/hypr/.local/bin/hypr-act` against a stub `hyprctl` and a fake runtime dir. `hypr-act <id> [args...]`: the stub runs the eval chunk in Lua against a fake `lib.act`, so ids and args holding `]]`, `]=]`, quotes, newlines or a leading newline arrive verbatim; a Lua error exits 5 with the message on stderr, no instance 3, a bad id or flag 2. `list`: the list is printed and the temp file removed, with no Hyprland answering stdout stays empty and the exit code is 3, with an eval that fails, times out or writes nothing it is 4, and a write that arrives late leaves no file behind.
- `input-vectors-lua`, `input-vectors-js`: `home/quickshell/tests/input_settings/vectors.tsv` through the Lua validator Hyprland uses (`config/input`) and the bar's (`HyprInputValidation.js`), so the two cannot drift apart. Need lua and node.
- `notification-markup`: `home/quickshell/tests/notification_markup.js`, the notification body sanitizer. Needs node.
- `toast-extent`: `home/quickshell/tests/toast_extent.js`, the toast drawer's window depth, stack height and hover settling in `features/notifications/ToastExtent.js`. Needs node.
- `directory-format`: `home/quickshell/tests/directory_format.js`, the directory segment's path shortening and app/path/file-name switches in `features/bar/DirectoryFormat.js`. Needs node.
- `island-shapes`: `home/quickshell/tests/island_shapes.js`, the fill-less island helpers in `ui/frames/IslandOutlines.js`, the popup cut-corner outlines in `ui/frames/PanelCuts.js` and that every `Style.island_shapes` entry has a kit and a label. Needs node.
- `drawer-shapes`: `home/quickshell/tests/drawer_shapes.js`, the drawer geometry in `ui/frames/DrawerGeometry.js` (layout, fill, outline, rim continuity with the screen frame) and `FrameGeometry.hole_rect`/`seam_of`. Needs node.
- `cava-viewers`: `home/quickshell/tests/cava_viewers.js`, the registry of what is drawing cava in `features/media/CavaViewers.js` (double register, destroy while shown, zero viewers). Needs node.
- `hover-popup`: `home/quickshell/tests/hover_popup.js`, the hover-open state machine in `features/popups/HoverPolicy.js` (module to popup and back, rapid enter and leave, pin against hover close, another monitor's popup). Needs node.
- `position-poll`: `home/quickshell/tests/position_poll.js`, how often the track position is re-read (`features/media/PositionPoll.js`: off with no viewer, 1 s playing, 2 s paused). Needs node.
- `media-settings`: `home/quickshell/tests/media_settings.js`, the cava-line migration and the `island_mode` rules in `features/media/MediaSettings.js` (existing `media.json` wins, corrupt file, strip and frame styles untouched). Needs node.
- `bar-layout`: `home/quickshell/tests/bar_layout.js`, the bar position in `features/bar/BarLayout.js` (rules, per-monitor overrides, the state file, the directory switches). Needs node.
- `bar-vertical`: `home/quickshell/tests/bar_vertical.js`, the side-bar column helpers in `features/bar/VerticalLayout.js` (cross width, text fit, unit drop, stacked clock). Needs node.
- `check-scope`, `check-cache`: which steps `--changed` picks (`lib/check/tests/scope.sh`), and the runner's scopes, keys, pass records and slot lock (`lib/check/tests/test_*.py`, `cache.sh`, `lock.sh`), and `shaders.sh`, the shaders step's tests. Any file under `lib/check/` reaches them, this README included.
- `packages`: duplicate package names across the manifests (`lib/check/steps/packages.sh`).
- `symlinks`, `whitespace`, `conflicts`, `git-diff-check`: tracked symlinks that dangle or leave the repo; trailing whitespace; conflict markers; and `git diff --check HEAD`.
- `ignored-integrations`: no voxcmd integration or replacement file is one git ignores (`lib/check/steps/ignored-integrations.sh`).

## Passes

A step that passes is recorded (`lib/check/passed.sh`) under a key hashing the step's definition (command, scope, needs, probe) and the content of the files it reads, the same files whose change makes `--changed` pick it (its scope in `scopes.py`). `scopes.py` itself is no input of other steps' keys, so editing it reruns only the steps it changes. A later run skips a step whose key already passed, uncommitted and untracked content included, and a pass is recorded only when the step's files did not change while it ran. The records are in the repository's common git dir, shared by every worktree.

A run that leaves the tree clean also records the tree: when every step passed for its content, or for `--changed <base>` on top of a base recorded as passed. A `--changed` run records that it passed against `<base>`, which is what the PR hook looks up. An `--only` run records its steps' passes, under the same keys a later `--changed` run looks up, but never the tree or a base. The shell steps (`shellcheck`, `shfmt`) key on the run's file lists, so for them pass `--only` the same `--changed` base the final run will use, or expect it to run them again. With `VOXCMD_ONLY_SECTIONS` set the voxcmd suites run in part, so no run records their pass, the tree or a base.

## Slots

At most `CHECK_HEAVY_SLOTS` heavy steps run at once on the machine, each holding a flock'd slot (`lib/check/lock.sh`) and waiting at most `CHECK_LOCK_WAIT_SECS` for one. The heavy steps are the five voxcmd suites and `voxtype-duck`; every other step, `voxcmd-rust` included, takes none. The five voxcmd suites also run one after another in a lane of their own, ahead of the rest, because they are timing-sensitive; `voxtype-duck` takes a slot but runs in the ordinary pool. On INT or TERM the running steps and their children are ended.
