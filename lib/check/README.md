# The check runner

`lib/check.sh` is a shim for `lib/check/runner.py` (stdlib Python 3.11+, always run with `-B`); it works as `sh lib/check.sh` and as `lib/check.sh`. The step table, the path rules and the shell file groups are in `lib/check/scopes.py`, where a new step goes. This file holds what the shim's header used to: the options, the environment, the step list and how passes are recorded. Editing the shim is scope "all" (every step reruns, about 4 minutes); editing this file reaches only `check-scope` and `check-cache`.

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

`--changed` always runs the "tree" steps: `git-diff-check`, `whitespace`, `conflicts`, `symlinks`, `packages`, `ignored-integrations`, `qml-ipc`, `readme-links` and `registry`. A change to `lib/check.sh`, the runner's own modules (`runner.py`, `keys.py`, `scopes.py`, `lock.sh`, `passed.sh`, `passed.py`), the `justfile`, `.claude/check-commands` or any path no rule in `scopes.py` claims runs everything. A Markdown file runs no step (see Scopes).

The parallel output of a step is buffered and a passing step prints one line; after the `FAILED:` line, the last 25 lines of each failing step follow. A step whose tool is missing prints `skip:` and passes. Run a suite through `--only` rather than by hand (a hook warns), so its pass is recorded and the final `--changed` run does not repeat it.

### Reading the summary

- `skipped (passed for these inputs)`: the step was not run because a recorded pass has the same key (below). It passed earlier; it was not left out.
- `skipped by scope`: no changed path reaches the step.
- `skipped by request`: named in `CHECK_SKIP_STEPS`.
- `skip: <reason>`: a tool the step needs is missing; the step counts as passing and no pass is recorded.

### Environment

- `CHECK_FULL=1` makes `--changed` run everything, and runs every step whatever passed before.
- `CHECK_JOBS` sets how many steps run at once (default half the cores, always clamped to 1-4); 1 runs them one after another with live output.
- `CHECK_SKIP_STEPS="step ..."` drops those steps whatever the scope says (the summary line lists them).
- `CHECK_HEAVY_SLOTS` (default 1) and `CHECK_LOCK_WAIT_SECS` (default 1200): see "Slots". `CHECK_NO_LOCK=1` runs the heavy steps without a slot, for a check that must never wait.
- Everything runs at nice 19 in the idle IO class.

### Where it runs on its own

Nothing runs it at the end of a turn. A commit runs it (`.claude/hooks/check-before-commit.sh`: `--paths-from` the committed files, `CHECK_NO_LOCK=1`, without the five voxcmd suites). A PR open only looks up a recorded pass (`.claude/hooks/check-before-pr.sh`). ship-batch runs it on each PR's branch, then on main. A worktree has no `repos/`, so its pass does not cover `symlinks` for the main checkout: run the check in the real checkout before merging.

## Scopes

A scope is a folder, and a change reaches the steps of the scopes its path falls in (`PATH_SCOPES` in `scopes.py`, first match wins). `lib/check.sh --plan --paths-from -` prints what a path reaches.

| Scope | Folders | Steps |
| --- | --- | --- |
| `hypr` | `home/hypr`, `system/etc/greetd` (not its `quickshell/`), `.luacheckrc` | stylua, luacheck, the hypr tests |
| `quickshell` | `home/quickshell`, `system/etc/greetd/quickshell`, the `qml*` check modules | qmllint, the qml-* checks, lock-skins, style-exports, shaders, time-format, the node and headless-qs tests, the input vectors |
| `voxclick`, `voxphrases`, `voxduck`, `voxrest`, `voxrust` | `home/voxcmd`, `home/voxtype`, `extras/voxcmd-firefox` | see Voxcmd scopes below |
| `install` | `lib/install`, `lib/common`, `packages/{snapper,devtools}.ini`, `home/calendar` | the install tests, calendar-sync |
| `hooks` | the agent hooks, and the `owner-test-bar`, `orchestrator` and `orchestrator-handoff` skills | the hook tests, owner-test-bar, reviewers (about a minute) |
| `skills` | the `ship-batch` and `merge-prs` skills | their suites (5 to 11 minutes) |
| `checkscope` | `lib/check`, `lib/plan_new.py`, the `lib/docs` generators | check-scope, check-cache |
| `docsgen` | the keymaps, the IpcHandler files, the `lib/docs` generators | docs-generated |

A file that a step of another folder reads gets one row naming both scopes, ahead of its folder's row. Markdown reaches no scope, in any folder; the exceptions are the two files `docs-generated` compares (`docs/keybinds.md`, the Quickshell README), found by grepping the steps and tests for `.md`. Other `.md` mentions there are strings in test data.

Tests are found by naming convention, so a new test file needs no entry in `STEPS` when it sits in one of these places (the step is named from the file, `_` as `-`; its `needs` are the tool of its family plus the optional tools the file's text names, such as `jq`, so a test is not skipped for a tool it never uses):

- `home/hypr/tests/*.sh`: `bash`, scope `hypr`. A `.lua` file there is a helper unless `scopes.py` names it as a Lua entry point.
- `home/quickshell/tests/*.js`: `node`, scope `quickshell`.
- `home/quickshell/tests/<name>/run.sh`: the headless-qs tests, scope `quickshell`.
- `lib/install/tests/*.sh`: `install-<name>`, scope `install`.
- `.claude/hooks/tests/*.sh` and `home/claude/.claude/hooks/tests/*.sh`: `hook-<name>`, scope `hooks`.

Everything else (the voxcmd suites, the lint steps, the skill tests) is listed in `STEPS` by hand.

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
- `qml-ipc`: every `qs ipc call` target and function in scripts, Lua, Rust, `tmux.conf` and test stubs is a typed function of an IpcHandler, and every handler is called, except `lib/check/qml-ipc.allow`, which fails when a line goes stale (`lib/check/steps/qml_ipc.py`). It also fails an IpcHandler under the Quickshell tree in a file not named `*Ipc.qml` (the `docsgen` scope finds the table's sources by that name) and a function with a type annotation that is still not exposed (it would silently drop out of the generated table). Always runs.
- `readme-links`: every link and backticked repo path in the Quickshell READMEs, and `docs/` exists, and every `#anchor` names a heading (`lib/check/steps/readme_links.py`). Always runs. This file is not read.
- `registry`: the action definitions refer to things that exist. `home/hypr/tests/act_refs.lua` loads every `lib/actions/defs/*.lua` headlessly and prints the action list; the step reads it in memory and discards it (no list is committed). It fails on an `Act` warning (unknown id, duplicate, bad params, undeclared `{param}`), a malformed or repeated id, an `ipc` action naming a function that is not a typed IpcHandler function (read by `qml_ipc.declared`) or passing it a different number of arguments than it has parameters, and a `command` action whose `~/` program no `home/<package>/` ships. It also loads `keymaps` under stubs (`home/hypr/tests/registry_binds.lua`) and fails on a bind that performs no action and on a typed IPC function no action calls, unless `lib/check/registry.allow` lists it with a reason (`bind <submap> <key>  # reason`, `ipc <target> <function>...  # reason`; `global`, `*` for every named submap, or a comma list as submaps); a line that matches nothing, or whose bind or function has an action now, is stale and fails, and so does a line without a reason. `custom/` binds are not loaded. Always runs. Fails, not skips, without lua (`lib/check/steps/registry.py`).
- `lock-skins`: `features/lock/skins/index.json` matches the skin files and audio importers (`lib/check/steps/lock-skins.sh`). Needs jq.
- `style-exports`: generated property lines in `theme/Style.qml` match `theme/StyleSchema.js` (`lib/check/steps/style-exports.sh`). Needs python3.
- `docs-generated`: the table between the markers in `docs/keybinds.md` matches the binds `home/hypr/tests/registry_binds.lua --labels` dumps from the shipped keymaps, and the IPC table in the Quickshell README matches the typed `IpcHandler` functions plus the action ids that perform them (`lib/check/steps/docs-generated.sh` runs `lib/docs/gen-keybinds --check` and `lib/docs/gen-ipc --check`). `just docs-gen` rewrites both. It has its own `docsgen` scope: keymaps and actions (`home/hypr/*`), `*Ipc.qml` files, the Quickshell README, `qml_ipc.py`, `qml_imports.py`, `qml_paths.py`, `docs/keybinds.md` and the generators under `lib/docs/` reach it, and an `*Ipc.qml` or README edit runs no stylua or luacheck. Needs lua and python3.
- `time-format`: no hand-built am/pm text in Quickshell QML/JS; clock text goes through `TimeFormat` (`lib/check/steps/time-format.sh`).
- `shaders`: each tracked Quickshell `.frag` rebuilds (qsb) to its committed `.frag.qsb` byte for byte, and its `// Rebuild:` header matches the command used; `just shaders` rewrites them (`lib/check/steps/shaders.sh`). Needs qsb (qt6-shadertools).
- `json-store`: `home/quickshell/tests/json_store/run.sh`, the lifecycle tests of `core/JsonStore.qml` in a headless qs. Needs qs, python3.
- `polled-command`: `home/quickshell/tests/polled_command/run.sh`, pins that Quickshell ends a Process's stdout at the exit even when a child holds the pipe, which `core/PolledCommand.qml` relies on. Needs qs, python3.
- `polled-file`: `home/quickshell/tests/polled_file/run.sh`, the read, failure, path-change, gating and interval tests of `core/PolledFile.qml` in a headless qs. Needs qs, python3.
- `colors-preview`: `home/quickshell/tests/colors_preview/run.sh`, which loads the Style pane with its cursor on the Colors rows (and a plain `RowsSection`, and Style with the cursor off them) beside a real `SettingsPanel` in a headless qs, wide, narrow and stacked under the rows, and fails unless the preview card sits inside the panel, never intersects the open Palette list and does not move when the list opens and sits at the panel's top with no blank band above it (#1293); a section with no preview must give the help card the whole panel. Needs qs.
- `restarting-stream`: `home/quickshell/tests/restarting_stream/run.sh`, the lifecycle tests of `core/RestartingStream.qml` (planned exits, re-probing, `wanted` during backoff) in a headless qs. Needs qs, python3.
- `voxcmd-phrases`: each phrase in `home/voxcmd/tests/phrases.tsv` routes as recorded (`run-phrases.sh`). Needs jq, fzf.
- `voxcmd-click`: voxcmd's click support (`run.sh`, with `run-sessions.sh`, `run-modes.sh`, `run-sequences.sh`, `run-overview.sh` and `run-monitors.sh` beside it). Needs jq, fzf.
- `voxcmd-calendar`: the calendar phrases against stubs (`run-calendar.sh`). Needs jq, fzf.
- `voxcmd-wake`: the wake word listener (`run-wake.sh`). Needs jq, fzf.
- `voxcmd-firefox`: the Firefox extension and its native-messaging host (`run-firefox-extension.sh`). Needs jq, fzf; the extension's script runs under node when present.
- `voxtype-duck`: `home/voxtype/tests/run-duck.sh`, the output-sink ducker. Needs python3.
- Voxcmd scopes: `voxclick` (`voxcmd-click`, the longest suite), `voxphrases` (`voxcmd-phrases`), `voxduck` (`voxtype-duck`), `voxrest` (`voxcmd-calendar`, `voxcmd-wake`, `voxcmd-firefox`) and `voxrust` (`voxcmd-rust`; the crate's test sources, snapshots and goldens reach only this one), so an edit to a file only one of them reads runs only that one. The crate's sources, the integrations, the shipped `share/` files, the replacement rules, voxtype-daemon and `extras/voxcmd-firefox` reach `voxclick`, `voxphrases` and `voxrest`, and the crate's sources and integrations `voxrust` too. A file under `home/voxcmd/tests` gets its row in `PATH_SCOPES` naming the scopes that read it, and a fixture with no row of its own falls to the `home/voxcmd/*` catch-all, which `lib/check/tests/test_voxcmd_suite_scopes.py` rejects; add the row when you add a fixture.
- `voxcmd-rust`: the voxcmd crate: `cargo fmt --check`, clippy `-D warnings`, `cargo test` (`lib/check/steps/voxcmd-rust.sh`). Takes no heavy slot and runs in the ordinary pool, not the serial lane. Needs cargo.
- `calendar-sync`: `home/calendar/tests/run.sh`. Runs only when python-icalendar and python-recurring-ical-events import.
- `calendar-sync-syntax`: the syntax check of `calendar-sync`; always runs when its scope is reached, whatever the libraries.
- `install-<test>`: one step per `lib/install/tests/*.sh` (found by name; see Scopes). They cover the Firefox policy and `install_voxcmd`, pacman and makepkg tuning, snapper setup, the CodeRabbit entry of the dev tools picker, the greeter keyring, log and monitors, the `migrate-quickshell-*` and `migrate-lock-assets` migrations, and `load.sh` (sourcing the install libraries prints nothing and never exits). Each needs the tools its file names (jq, zsh).
- `hook-<test>`: one step per `.claude/hooks/tests/*.sh` and `home/claude/.claude/hooks/tests/*.sh` (found by name; see Scopes), each the test of the hook of that name. Each needs jq, plus tmux and flock where its file names them.
- `owner-test-bar`: the owner-test-bar skill's `tests/run.sh`, when it changes. Needs jq.
- `ship-batch`, `merge-prs`: those skills' `tests/run.sh`, when either changes.
- `reviewers`: the orchestrator skill's `tests/run.sh` (registry resolver), when `reviewers.json`, `reviewers.sh` or its tests change.
- `frame-lone-flush`: `home/hypr/tests/frame_lone_flush.lua` runs `config/general/frame.lua` against a stubbed `hl` and checks the lone-window flush opt-out (when it starts and ends) and the workspace animation swap. Needs lua.
- `bind-action`: `home/hypr/tests/bind_action.lua` runs `lib/actions/defs/tools.lua` against a stubbed `hl`: the 14 tool actions register the keys, extra keys, labels and `submap_universal` flags written out in the test with no warning, perform the command written out in the test through `Ipc`/`Cmd` argv, and their binds can be unbound. Needs lua.
- `shadow-action`: `home/hypr/tests/shadow-action.sh` sources `.claude/skills/shadow/shadow.sh` with `ipc` stubbed to a recorder. `action x <id> [params]` resolves the id headlessly (`act_refs.lua --resolve`, the parameter checks of `hypr-act`) and sends an ipc-kind action as the `ipc` call (`popup.open weather` becomes `x popup open weather`, a param with spaces stays one word); a command- or lua-kind action, an unknown id and a bad or missing param exit 5 with a message and no `ipc` call. Needs lua and jq.
- `act-lib`: `home/hypr/tests/act.lua` runs `lib/act.lua` against a stubbed `hl`: `Act.define`/`bind` register keys (`bind`'s `desc` replaces the label on one key or, as `false`, hides it) and skip bad definitions with a warning, `run`/`run_cli` check and coerce typed params, `Ipc`/`Cmd` carry their data and render `{param}` in one pass, and hostile strings (quotes, `]]`, newlines, `{param}`, leading `-`) round-trip through `sh` and a Lua long-string chunk. `Act.list_json` and `write_list` produce the list `hypr-act list` prints. Needs lua.
- `act-global`: `home/hypr/tests/act-global.sh` runs `act_global.lua` against a stubbed `hl` and the keymaps `keymaps/global/{general,workspace,media,mouse}.lua` under four Config shapes (vim keys or arrows, global or persistent workspaces, monitor counts, with and without a leader): every registered bind must match `home/hypr/tests/fixtures/act_global_binds.tsv` (key, which-key label, flags, what it dispatches), the action ids must exist, and the workspace ids must follow `Config.persistent_workspaces` at run time. The repo's `git status` must be unchanged afterwards. Needs lua.
- `act-launch`: `home/hypr/tests/act-launch.sh` runs `act_launch.lua` (stubs in `act_stubs.lua`) against a stubbed `hl` and the keymaps `keymaps/global/{shortcuts,tools}.lua` with and without a leader: every registered bind must match `home/hypr/tests/fixtures/act_launch_binds.tsv` (submap, key, which-key label, flags, what it does), the launch action ids must exist with their labels, and the file-manager actions must read `Config` when they run. The repo's `git status` must be unchanged afterwards. Needs lua.
- `act-submap-rows`: `home/hypr/tests/act-submap-rows.sh` runs `act_submap_rows.lua` against a stubbed `hl`, the global keymaps and the Leader, Applications, Go, System and Bar submaps with and without a leader and monitors: every bind in those submaps must match `home/hypr/tests/fixtures/act_submap_rows_binds.tsv` (key, which-key label, flags, what it does), `apps.focus` must accept every `Apps.map` name, and the row form (`{ key, "id" }`, `{ key, { id, args } }`) must take the action's label unless the row gives one, drop only the row with an unknown id or bad args with a warning, and keep one-shot and `keep` behaviour. The repo's `git status` must be unchanged afterwards. Needs lua.
- `act-stateful`: `home/hypr/tests/act-stateful.sh` runs `act_stateful.lua` against a stubbed `hl`, the global keymaps and the Windows, Cursor, Quick Click, Groups, Move, Resize and Delete submaps under four Config shapes (default, no leader with monitors, persistent workspaces, vim_mode off): every bind in those submaps must match `home/hypr/tests/fixtures/act_stateful_binds.tsv` (key, which-key label, flags, what it does). It also checks the shared state: the Windows selection survives between presses, acts on every selected window and does not leak to other submaps, the next visit or a reload; Cursor scroll timers do not pile up across presses and stop on release or on leaving the submap; `catchall = "stay"` submaps still swallow unbound keys; and each submap file loads alone without an Act warning. The repo's `git status` must be unchanged afterwards. Needs lua.
- `act-ipc`: `home/hypr/tests/act-ipc.sh` runs `act_ipc.lua`, which loads the keyless IPC action definitions (`lib/actions/defs/{notifications,style,lock,power,screenshot,zoom,overview,settings,launcher}.lua`) under a stubbed `hl` and runs each id with sample arguments: the `qs-ipc call <target> <function> <args>` line it would send must match the table, a bad enum, bool or int is refused, and no such action has a key. It then loads `keymaps.global`, the entry a live session loads, and finds all of them registered, so a defs file no keymap requires fails here. Last it loads `keymaps.global` and `keymaps.submaps` with `pickers.lua` raising after its defines and `power.lua` failing to parse: the load must finish, the other actions and submaps register, each broken file is warned about once, and none runs twice (no "already defined" warning). Then it loads both again with `keymaps/global/power.lua` failing to parse and the Go submap raising: every other bind of a clean load must remain, none of theirs, and each is warned about once. Last, with `power.lua` raising after its binds and the Go submap body raising after one bind: no submap body raises inside `hl.define_submap`, the later submaps' entry keys stay global (in the stub and in `Bind.is_bound`) and Go gets no entry key. The `registry` step checks the targets and functions they call and the number of arguments each passes. The repo's `git status` must be unchanged afterwards. Needs lua.
- `theme-state`: `home/hypr/tests/theme_state.lua` loads `theme/init.lua` under a temp `HOME` with stubbed generators: a saved theme in the state file is restored and the file left alone; on a first run (no state file, or an empty one) the legacy `~/.config/hypr/theme/.current_theme` is taken, else the default is kept, and the state file is written. Needs lua.
- `hypr-act`: `home/hypr/tests/hypr-act.sh` runs `home/hypr/.local/bin/hypr-act` against a stub `hyprctl` and a fake runtime dir. `hypr-act <id> [args...]`: the stub runs the eval chunk in Lua against a fake `lib.act`, so ids and args holding `]]`, `]=]`, quotes, newlines or a leading newline arrive verbatim; a Lua error exits 5 with the message on stderr, no instance 3, a bad id or flag 2. `list`: the list is printed and the temp file removed, with no Hyprland answering stdout stays empty and the exit code is 3, with an eval that fails, times out or writes nothing it is 4, and a write that arrives late leaves no file behind.
- `input-vectors-lua`, `input-vectors-js`: `home/quickshell/tests/input_settings/vectors.tsv` through the Lua validator Hyprland uses (`config/input`) and the bar's (`HyprInputValidation.js`), so the two cannot drift apart. Need lua and node.
- `notification-markup`: `home/quickshell/tests/notification_markup.js`, the notification body sanitizer. Needs node.
- `toast-extent`: `home/quickshell/tests/toast_extent.js`, the toast drawer's window depth, stack height and hover settling in `features/notifications/ToastExtent.js`. Needs node.
- `picker-start-mode`: `home/quickshell/tests/picker_start_mode.js`, the mode a bottom-docked picker opens in (its own choice, else its Browse or Search group) and the typing.json keys behind it, in `features/launcher/StartMode.js`. Needs node.
- `directory-format`: `home/quickshell/tests/directory_format.js`, the directory segment's path shortening and app/path/file-name switches in `features/bar/DirectoryFormat.js`. Needs node.
- `island-shapes`: `home/quickshell/tests/island_shapes.js`, the fill-less island helpers in `ui/frames/IslandOutlines.js`, the popup cut-corner outlines in `ui/frames/PanelCuts.js` and that every `Style.island_shapes` entry has a kit and a label. Needs node.
- `drawer-shapes`: `home/quickshell/tests/drawer_shapes.js`, the drawer geometry in `ui/frames/DrawerGeometry.js` (layout, fill, outline, rim continuity with the screen frame) and `FrameGeometry.hole_rect`/`seam_of`. Needs node.
- `style-title-readout`: `home/quickshell/tests/style_title_readout.js`, the `title_readout_size` token in `theme/StyleSchema.js`: default 0 keeps the popup title at fs(-5), and a style that sets it sets a positive size. Needs node.
- `cava-viewers`: `home/quickshell/tests/cava_viewers.js`, the registry of what is drawing cava in `features/media/CavaViewers.js` (double register, destroy while shown, zero viewers). Needs node.
- `ansi-text`: `home/quickshell/tests/ansi_text.js`, the SGR to StyledText converter in `features/launcher/AnsiText.js` behind the agent sessions preview (colour forms, escaping, dropped escapes). Needs node.
- `agent-sessions`: `home/quickshell/tests/agent_sessions.js`, the row parsing, tmux capture argv and card tails in `features/launcher/AgentSessions.js` (bad JSON, state labels, home shortening, no `-S` without a socket, the pane width line, the last line with words, the tails script run against a stub tmux). Needs node.
- `picker-browse`: `home/quickshell/tests/picker_browse.js`, the browse picker's preview sizes (`=`, `-`, `p`) and how the card rows share the body with the preview, in `features/launcher/BrowseLayout.js`. Needs node.
- `hover-popup`: `home/quickshell/tests/hover_popup.js`, the hover-open state machine in `features/popups/HoverPolicy.js` (module to popup and back, rapid enter and leave, pin against hover close, another monitor's popup). Needs node.
- `position-poll`: `home/quickshell/tests/position_poll.js`, how often the track position is re-read (`features/media/PositionPoll.js`: off with no viewer, 1 s playing, 2 s paused). Needs node.
- `media-text`: `home/quickshell/tests/media_text.js`, the media well's text clipping, inline and stacked layout, time format and marquee gate in `features/bar/MediaText.js`. Needs node.
- `media-settings`: `home/quickshell/tests/media_settings.js`, the cava-line migration and the `island_mode` rules in `features/media/MediaSettings.js` (existing `media.json` wins, corrupt file, strip and frame styles untouched). Needs node.
- `media-sample`: `home/quickshell/tests/media_sample.js`, when Settings > Media previews the live player or the sample track, and the sample's levels and position in `features/media/MediaSample.js`. Needs node.
- `settings-sections`: `home/quickshell/tests/settings_sections.js`, the Settings section list in `features/settings/Sections.js`: unique ids, existing sources, and the ids of merged sections (`colors`, `clock`, `calendar`, `login`) still resolving to the merged section and a heading in it. Needs node.
- `settings-scale`: `home/quickshell/tests/settings_scale.js`, the Settings text bump over screen height (none at 1080p and below) and the color lift in `features/settings/SettingsScale.js` (Game Boy palette included). Needs node.
- `scroll-cue`: `home/quickshell/tests/scroll_cue.js`, which edges of a Settings list or browse picker hide content and that a revealed row stays clear of the scroll fade (`ui/scroll/ScrollCue.js`). Needs node.
- `bar-layout`: `home/quickshell/tests/bar_layout.js`, the bar position in `features/bar/BarLayout.js` (rules, per-monitor overrides, the state file, the directory switches). Needs node.
- `bar-vertical`: `home/quickshell/tests/bar_vertical.js`, the side-bar column helpers in `features/bar/VerticalLayout.js` (cross width, text fit, unit drop, stacked clock). Needs node.
- `check-scope`, `check-cache`: which steps `--changed` picks (`lib/check/tests/scope.sh`), and the runner's scopes, keys, pass records and slot lock (`lib/check/tests/test_*.py`, `cache.sh`, `lock.sh`), and `shaders.sh`, the shaders step's tests. Any file under `lib/check/` reaches them, this README included.
- `packages`: duplicate package names across the manifests (`lib/check/steps/packages.sh`).
- `symlinks`, `whitespace`, `conflicts`, `git-diff-check`: tracked symlinks that dangle or leave the repo; trailing whitespace; conflict markers; and `git diff --check HEAD`.
- `ignored-integrations`: no voxcmd integration or replacement file is one git ignores (`lib/check/steps/ignored-integrations.sh`).

## Passes

A step that passes is recorded (`lib/check/passed.sh`) under a key hashing the step's definition (command, scope, needs, probe) and the content of the files it reads, the same files whose change makes `--changed` pick it (its scope in `scopes.py`). `scopes.py` itself is no input of other steps' keys, so editing it reruns only the steps it changes. A later run skips a step whose key already passed, uncommitted and untracked content included, and a pass is recorded only when the step's files did not change while it ran. The records are in the repository's common git dir, shared by every worktree. A new `Step` field that can change a pass goes in `keys.DEFINITION_FIELDS` (a guard test fails otherwise). Branches cut before the Python port share no passes with this runner (`keys.py` says why).

A run that leaves the tree clean also records the tree: when every step passed for its content, or for `--changed <base>` on top of a base recorded as passed. A `--changed` run records that it passed against `<base>`, which is what the PR hook looks up. An `--only` run records its steps' passes, under the same keys a later `--changed` run looks up, but never the tree or a base. The shell steps (`shellcheck`, `shfmt`) key on the run's file lists, so for them pass `--only` the same `--changed` base the final run will use, or expect it to run them again. With `VOXCMD_ONLY_SECTIONS` set the voxcmd suites run in part, so no run records their pass, the tree or a base.

## Slots

At most `CHECK_HEAVY_SLOTS` heavy steps run at once on the machine, each holding a flock'd slot (`lib/check/lock.sh`) and waiting at most `CHECK_LOCK_WAIT_SECS` for one. The heavy steps are the five voxcmd suites and `voxtype-duck`; every other step, `voxcmd-rust` included, takes none. The five voxcmd suites also run one after another in a lane of their own, ahead of the rest, because they are timing-sensitive; `voxtype-duck` takes a slot but runs in the ordinary pool. On INT or TERM the running steps and their children are ended.
