# Quickshell

The desktop shell for this Hyprland setup, written for [Quickshell](https://quickshell.org). One config replaces Waybar, swaync, the rofi pickers, the lock screen and the greeter UI. Every monitor gets its own bar, and all colors follow the active Oasis theme (the GoldenEye style's Classic watch colours and its game iconography are the exception, see [Styles](theme/README.md#styles)).

Tested with Quickshell 0.3.1 (the `quickshell` package in the Arch repos); the installer warns if yours is older.

Hyprland starts it with `qs -n` (see `home/hypr/.config/hypr/config/autostart/`). Hyprland binds reach it over IPC. When it isn't running, the pickers fall back to the menu in `Config.app.menu` (rofi by default; what fuzzel, wofi and other menus cover is in `home/hypr/.config/hypr/README.md`) and the lock to hyprlock.

## Layout

| Path          | Purpose                                                                                    |
| ------------- | ------------------------------------------------------------------------------------------ |
| `shell.qml`   | Entry point: a bar per monitor, then every popup, picker provider, IPC handler and overlay |
| `services/`   | `Palettes`, the one singleton not yet moved into a feature (`shell.qml` still imports it so Quickshell registers the module) |
| `ui/`         | Shared widgets: `menu/` (rows, tabs), `frames/` (brackets and the pieces a frame stack is built from), `gauges/` (`Meter`, `AtbBar`, `TickRuler`...), `keys/` (key badges, controller badges, and the hint bar parts `HintPlate`, `HintModeBlock` and `HintGroups`), `scroll/` (`ScrollCue`, the fade and caret of a list that scrolls on), `effects/` (dither, scanlines, sheen, sprites) |
| `styles/`     | One folder per style with the pieces that only that style draws: `tokens.js` (its token overrides), `icons.js` (its bar icon set, where it has one), `widgets/` and `sounds/` (the style's sound pack), and for snes `popups/`; `goldeneye/` also holds `Watch.js` (the watch colors), `watch_tokens.js` and the watch parts its lock skin shares (`PanelShape`, `SegmentArc`, `WatchHands`, `static.frag`). `index.js` builds every style's token set and `IconSets.js` registers the icon sets |
| `features/`   | One folder per feature, listed under Features below |
| `core/`       | `Paths.qml` (XDG dirs), `WindowVisibility.js` (which Hyprland windows a monitor shows: its workspace, its open special workspace, pinned ones), `JsonStore.qml` (one JSON settings file: debounced atomic save, watch, extras kept; or with `read_only` a follower of a file another program writes), `Fuzzy.js` (the fuzzy matcher), `RestartingStream.qml` (a streamed command restarted with backoff, re-probed for its tool, planned exits not counted as failures), `PolledCommand.qml` (a command run on a timer or on demand, one result per run) and `PolledFile.qml` (a file read on a timer or on demand, `loaded` or `load_failed` per read) |
| `theme/`      | `Theme.qml` (colors from the Oasis theme), `Style.qml` (the active style's tokens), `StyleSchema.js` (every token's type, default and doc) and `BundledFonts.qml` (registers the bundled fonts) |
| `assets/fonts/` | Bundled OFL fonts, registered for the whole shell                                        |
| `sounds/`     | `alarm.ogg` and `mgs2/`, the sounds that belong to no style (each style's pack is in `styles/<style>/sounds/`) |
| `scripts/`    | Helpers the shell runs: greeter data, lock backdrop, audio importers, sound generator; `gen-style-exports` for `Style.qml` |
| `bars.json`   | Tracked bar layout per monitor, matched by description or connector name                   |

Where the docs are: [theme and styles](theme/README.md) (tokens, fonts), [style sounds](styles/README.md), [`custom/`](custom/README.md) and [`assets/fonts/`](assets/fonts/README.md).

### Features

One folder per feature (`features/<name>/`); a linked folder has its own README, the rest are described here.

- `power/` holds `Power` (AC and battery state), its IPC handler and settings, the Power and Battery popups, and `PowerConfirm`.
- [`clock/`](features/clock/README.md): Clock, calendar and time zones
- [`weather/`](features/weather/README.md): Weather settings, alerts, fixtures and views
- [`launcher/`](features/launcher/README.md) holds the fuzzy picker, its `Pickers` registry and IPC handler, its providers (agents, apps, clipboard, dirs, emoji, keybinds, choices), the HyprVim `:` prompt in `hyprvim/`, and `TypingSettings`.
- `screen_select/` holds `RegionSelector`, its toolbar and key overlays, and the `cursors/`, `loupe/` and `targets/` skins.
- `display/` holds `Displays` and `DisplayLayout.js` (monitor layout), `Backlight`, the brightness and zoom IPC handlers, and the overview zoom `Zoom` with its loupe and reticle.
- `media/` holds `MediaState` (MPRIS players), `CavaState` (the cava feed, run while a registered viewer draws it; `CavaViewers.js`), the media popup with its album art, seek bar, round buttons and cava strip, and the volume popup.
- `osd/` holds the on-screen display for brightness, volume, power and voice state.
- `screenshot/` holds `Screenshot` (capture and recording state), its IPC handler, `ScreenShare` and the screenshot popup.
- [`notifications/`](features/notifications/README.md): Notification history and Do Not Disturb
- `start/` holds the Start popup and its NES menu.
- `tray/` holds the system tray popup.
- `system/` holds the system popup and the `SysStats` and `SystemStat` singletons.
- `bluetooth/` holds the Bluetooth popup.
- `network/` holds the network popup with its Wi-Fi rows, header, details and password panes and `Network.js`.
- `keeptabs/` holds `KeeptabsState`, `ClaudeUsageState`, `UsageProjection.js` (where each weekly limit is heading at the week's pace so far), the keeptabs popup and its per-style Agents and Usage layouts in `views/`.
- `updates/` holds `UpdatesState` (pending package counts), the updates popup and its NES inventory.
- [`overview/`](features/overview/README.md): Workspace overview, voice contract and tmux tools
- [`bar/`](features/bar/README.md): Bar layout and modules, command status
- [`bar_editor/`](features/bar_editor/README.md): The full-screen editor for the bar's modules, opened over IPC
- `voice/` holds `VoxSessionState` and `VoxWakeState` (the voxcmd session and wake-word files), `VoxtypeState` and `VoxtypeAudioState` (dictation state and samples), `VoiceSettings`, and the click hints: `ClickHints`, its IPC handler and `ClickHintsOverlay`.
- [`settings/`](features/settings/README.md): The Settings panel and its saved state files
- [`popups/`](features/popups/README.md): Popup framework and shared popup keys
- `audio/` holds `ThemeAudio` (the sound packs and their volumes) and the `sound` IPC handler `SoundIpc`.
- `style/` holds `StyleIpc`, the `style` IPC handler (style, lock skin and sound-pack calls).
- `windows/` holds `WindowState` (Hyprland windows, most recently focused first).
- `submap_hints/` holds `SubmapHintBar`, the compact key hints shown while Hyprland is in a submap whose `Submap.define` has a `hint` (Windows, Resize, Move, Cursor; a plain-centre frame drawer opposite the bar with the screen frame on, a floating plate without), and its `submap_hints` IPC handler. The hints themselves are kept by name in `bar/SubmapState`. In a submap with `targets` (Windows, Resize, Move), `WindowTargetOverlay` numbers the selected windows on every screen (Hyprland draws their border), from `WindowTargetState` (the selection Hyprland sends and the window places it rereads on Hyprland events).
- [`lock/`](features/lock/README.md): Lock screen, skins and greeter

## IPC

Anything the shell exposes can be called from a script or bind with `qs ipc call <target> <function> [args]`. Hyprland calls it through `~/.config/hypr/scripts/qs-ipc`, a wrapper that finds the running bar even when it was started from a worktree. The examples below use that wrapper:

```bash
qs-ipc call popup open volume
qs-ipc call picker open apps
qs-ipc call lock state
qs-ipc show        # list every target and function
```

`qs-picker <provider> <fallback> [mode]` in the same folder opens a picker, or runs the fallback command when no bar answers.

Every function the shell exposes, with its typed signature and, where an action in `home/hypr/.config/hypr/lib/act/defs` performs it, that action's id. The table is generated from the `IpcHandler` declarations; `just docs-gen` rewrites it.

<!-- BEGIN generated -->
| Target | Signature | Action id |
| --- | --- | --- |
| `bareditor` | `open(monitor: string): string` | `bareditor.open` |
| `bareditor` | `close(): string` | `bareditor.close` |
| `bareditor` | `toggle(): string` | `bareditor.toggle` |
| `bareditor` | `state(): string` |  |
| `brightness` | `refresh(): void` |  |
| `calendar` | `refresh(): void` |  |
| `calendar` | `open_day(date: string): string` |  |
| `clickhints` | `open(spec_path: string): string` |  |
| `clickhints` | `dismiss(result_path: string): void` |  |
| `clickhints` | `state(): string` |  |
| `cmdstatus` | `refresh(id: string): string` |  |
| `confirm` | `ask(question: string, result_path: string): string` |  |
| `confirm` | `dismiss(result_path: string): void` |  |
| `hyprvim_prompt` | `open(path: string): string` |  |
| `hyprvim_prompt` | `close(): void` |  |
| `hyprvim_whichkey` | `open(path: string): void` |  |
| `hyprvim_whichkey` | `close(): void` |  |
| `lock` | `lock(): string` | `lock.open` |
| `lock` | `lock_auto(): string` |  |
| `lock` | `preview(name: string): string` |  |
| `lock` | `preview_close(): string` |  |
| `lock` | `state(): string` |  |
| `notifications` | `toggle_dnd(): void` | `notifications.toggle_dnd` |
| `notifications` | `get_dnd(): bool` |  |
| `notifications` | `clear_all(): void` | `notifications.clear_all` |
| `notifications` | `dismiss_latest(): void` | `notifications.dismiss_latest` |
| `notifications` | `dismiss_all(): void` | `notifications.dismiss_all` |
| `notifications` | `focus_toast(direction: string): string` |  |
| `notifications` | `get_last(): string` |  |
| `notifications` | `history(count: int, app: string): string` |  |
| `notifications` | `has_toast(): bool` |  |
| `notifications` | `open(): void` |  |
| `notifications` | `close(): void` |  |
| `osd` | `state(): string` |  |
| `overview` | `save_session(target_name: string): string` |  |
| `overview` | `open(): string` | `overview.open` |
| `overview` | `close(): string` | `overview.close` |
| `overview` | `search(): string` | `overview.search` |
| `overview` | `move_follow(): string` | `overview.move` |
| `overview` | `move_silent(): string` | `overview.move_silent` |
| `overview` | `toggle(): string` | `overview.toggle` |
| `overview` | `state(): string` |  |
| `overview` | `act(verb: string, args: string): string` |  |
| `picker` | `open(name: string): string` | `picker.open` |
| `picker` | `open_with(name: string, arg: string): string` |  |
| `picker` | `toggle(name: string): string` | `picker.toggle` |
| `picker` | `close(): void` | `picker.close` |
| `picker` | `answer(token: string, text: string): string` |  |
| `picker` | `expand(index: int, token: string): string` |  |
| `picker` | `cancel(token: string): string` |  |
| `popup` | `open(name: string): void` | `popup.open` |
| `popup` | `close(): void` |  |
| `popup` | `toggle(name: string): void` |  |
| `popup` | `focus(): string` |  |
| `popup` | `keyboard(): string` |  |
| `popup` | `state(): string` |  |
| `power` | `confirm(action: string): void` | `power.confirm` |
| `power` | `run(action: string): void` |  |
| `screenshot` | `open(): string` | `screenshot.menu` |
| `screenshot` | `close(): void` |  |
| `screenshot` | `toggle(): string` |  |
| `screenshot` | `select(frozen: bool, preset: string): string` | `screenshot.select` |
| `screenshot` | `pick(mode: string, preset: string): string` |  |
| `screenshot` | `share(windows: string, reply: string): string` |  |
| `screenshot` | `stop_recording(): void` | `screenshot.stop_recording` |
| `screenshot` | `recording_started(pid: string): string` |  |
| `screenshot` | `recording_stopped(): void` |  |
| `settings` | `open(section: string): void` | `settings.open` |
| `settings` | `toggle(): void` | `settings.toggle` |
| `settings` | `view(section: string, screen: string): bool` |  |
| `settings` | `cursor(index: int): void` |  |
| `settings` | `step(delta: int): void` |  |
| `settings` | `activate(): void` |  |
| `settings` | `back(): void` |  |
| `settings` | `hide(): void` |  |
| `sound` | `play(kind: string): string` |  |
| `style` | `set(name: string): void` | `style.set` |
| `style` | `cycle(): void` | `style.cycle` |
| `style` | `get(): string` |  |
| `style` | `set_effects_pack(name: string): string` |  |
| `style` | `get_effects_pack(): string` |  |
| `style` | `set_ui_sounds(on: bool): void` |  |
| `style` | `get_ui_sounds(): bool` |  |
| `style` | `set_lock(name: string): string` |  |
| `style` | `get_lock(): string` |  |
| `style` | `set_lock_tint(name: string): string` |  |
| `style` | `get_lock_tint(): string` |  |
| `style` | `set_lock_backdrop(name: string): string` |  |
| `style` | `get_lock_backdrop(): string` |  |
| `style` | `toggle_cava_line(): void` |  |
| `style` | `get_cava_line(): bool` |  |
| `submap_hints` | `set(json: string): string` |  |
| `submap_hints` | `selection(json: string): string` |  |
| `submap_hints` | `clear(generation: string): void` |  |
| `tmux_overview` | `open(): string` | `tmux.overview` |
| `tmux_overview` | `close(): string` | `tmux.close` |
| `tmux_overview` | `search(): string` | `tmux.search` |
| `tmux_overview` | `toggle(): string` | `tmux.toggle` |
| `tmux_overview` | `state(): string` |  |
| `transition` | `play(name: string): void` |  |
| `weather` | `preview(name: string): string` |  |
| `weather` | `previewing(): string` |  |
| `zoom` | `start(): void` |  |
| `zoom` | `stop(): void` |  |
| `zoom` | `toggle(): void` | `zoom.toggle` |
| `zoom` | `step(delta: int): void` | `zoom.step` |
| `zoom` | `size(delta: int): void` | `zoom.size` |
| `zoom` | `full(): void` | `zoom.full` |
<!-- END generated -->

Notes on the targets whose names do not say enough:

- `transition`: `play <kind or style>` takes a transition kind or a style name.
- `picker`: `open_with <name> <arg>` opens the picker and hands `arg` to its provider: `delete` for `clipboard`, the file manager for `dirs`, a set for `emoji`, a submap for `keybinds`, the spec path for `choices`. `answer <token> <text>`, `expand <index> <token>` and `cancel <token>` are voice answers to the open picker (see [Voice answers](features/launcher/README.md#voice-answers)).
- `lock`: `preview <style>` previews a lock style; `lock_auto` waits for the first key before the music starts.
- `sound`: `play <kind>` plays a Theme audio sound if its category is on; `play alarm` always rings.
- `overview`: `state` is `open` or `closed`; for `act <verb> <args>` see [Workspace overview and voice](features/overview/README.md).
- `notifications`: `get_last` returns the newest history entry as JSON; see [Notifications](features/notifications/README.md).
- `power`: `confirm` takes `lock`, `logout`, `reboot` or `poweroff`.
- `confirm`: `ask <question> <result_path>` drops the yes/no card from the center island and writes `yes` or `no` to the path (No, Esc, the scrim and 10s without an answer are all `no`, the countdown waiting while voxtype records or transcribes); `dismiss <result_path>` closes that card without writing. `voxcmd ask confirm` is the shell caller.
- `clickhints`: `open <spec_path>` shows numbered boxes over the screen from a JSON file `{label, choices: [{label, x, y, w, h}], result_path}` (global logical coordinates, at most ten). It writes the picked number, or an empty line for Esc, a click outside a box and 10s without an answer (the countdown waiting while voxtype records or transcribes), to the path, and returns `ok` (anything else means fall back to a text picker); `dismiss <result_path>` closes it without writing; `state` is `open` or `closed`. `voxcmd ask hints` is its caller.
- `weather`: `preview <fixture|off>` overlays a `features/weather/WeatherFixture.js` fixture on the live data; see [Weather views](features/weather/README.md).
- `calendar`: `refresh` rereads the calendar cache; `open_day <YYYY-MM-DD>` opens the clock popup on that day.
- `cmdstatus`: `refresh <id>` with `""` refreshes every entry.
- `hyprvim_whichkey`, `hyprvim_prompt`: external API, the HyprVim which-key HUD and `:` prompt, each with `open` and `close`, called by the hyprvim plugin.
- `submap_hints`: `clear <generation>` drops every stored hint and the selection (sent on each Hyprland config load, with that load's selection generation); `set <json>` stores a submap's hint bar (`{name, groups: [{name, keys: [[cap, label]]}], footer: [[cap, label]]}`), shown while Hyprland is in that submap; `home/hypr/.config/hypr/lib/key/submap_hint.lua` sends it on every entry. `selection <json>` stores the window selection (`{generation, serial, windows: ["0x..."]}`) that `home/hypr/.config/hypr/lib/selection.lua` sends on each change and on entering Windows, Resize or Move; one older by (generation, serial) is ignored (`features/submap_hints/SelectionOrder.js`).

Popup names are the `LazyPopup` names in `shell.qml`: `start`, `settings`, `power`, `clock`, `volume`, `battery`, `bluetooth`, `system`, `tray`, `network`, `keeptabs`, `weather`, `updates`, `media`, `screenshot`, `notifications`, `picker`.

## Naming singletons

A singleton is named for what it holds: `Settings` for the user's saved choices (`ClockSettings`, `BarSettings`), `State` for live data read from outside (the system, a daemon, a file the user does not edit), and otherwise a plain noun for what it is (`Sessions`, `Popups`). A name ending in `Config`, `Store` or `Manager` says which of those it is only by accident, so `lib/check/steps/qml_singleton_names.py` fails any `pragma Singleton` file named that way unless `lib/check/qml-singleton-names.allow` lists it as a temporary exception; the rename that removes the name deletes the line.

## Key conventions

Keys stay consistent across surfaces; new popups, pickers and skins follow these. The repo-wide interaction conventions are in [AGENTS.md](../../../../AGENTS.md#interaction-conventions).

- Popups (`features/popups/frames/Popup.qml`, keys in `PopupKeys.qml`): Tab/Shift+Tab step the top tabs, `[`/`]` the bottom views; a popup with one level answers both. Number keys pick a tab. Clock: Tab and `[`/`]` cycle timezones.
- Settings panes: `h` (and Esc, Tab) goes back to the sidebar and `l` or Enter goes in, like a file manager; a pane with nested views (Sessions) steps `h` and Esc up one view at a time and reaches the sidebar from its top view. A row's value steps with `l`/Space forward and Shift+`H`/`L` either way, so a section leaves plain `h` unused. `{`/`}` jump between headings (`RowsSection`). `Ctrl+D`/`Ctrl+U` move half a page in the section list, a pane and an open list (`SettingsPopup.half_page_pane`), except that while typing in an open list's filter (INSERT) `Ctrl+U` clears it and only `Ctrl+D` pages; in NORMAL both page.
- Overviews (workspace and share picker): `s` selects a whole screen, `w` sends the selected workspace to a monitor and `W` swaps it (both confirm with Enter), Tab/Shift+Tab switch regular and special workspaces, `[`/`]` cycle windows, `f` toggles the view; in the share picker `r` opens the region selector and Esc there comes back.
- A popup action that opens a window launches it through `Popups.after_close(fn)`, never `Popups.close()` then a launch: a window that maps while the popup holds the keyboard ends up unfocused.
- Lock and greeter input is a vim model owned by the shared router (`Lock.key`, `Greeter.key`): NORMAL while nothing is typed, where `h/j/k/l` navigate skin menus and `h`/`l` do nothing on vertical lists; `i` or any other printable key enters INSERT (`-- INSERT --` shows bottom-left); Esc on an empty buffer returns to NORMAL. The skin contract is in [the lock README](features/lock/README.md).
- Forgetting and deleting saved data ask `y`/`n` first, naming what goes, unless `u` undoes it (the bar editor's `x` in VISUAL); `q` still closes from the prompt.
- Picker lists step rows with Tab/Shift+Tab, except a provider whose items expand (`PickerProvider.expands`, e.g. Voice Help): there Tab expands the selected item, as Tab completes in HyprVim's prompt, and Backspace on an empty search goes back. Browse pickers (agents, clipboard) move with `hjkl` and never step rows with Tab: their Tab/Shift+Tab swaps in the provider's `alt_preview` (the agents' Claude usage) and otherwise does nothing.
- Full-screen modes (pickers, zoom) follow `RegionSelector`: Quickshell owns keyboard and pointer, with a `?` help box, never a Hyprland submap. Modes where the keyboard moves the pointer load the skin cursor from `features/screen_select/cursors`; others (the bar editor) keep the system cursor.
- Never hand-edit the `BEGIN generated` block in `Style.qml`: edit `theme/StyleSchema.js` and run `scripts/gen-style-exports`. Adding a style or token: [theme README](theme/README.md).
- Times use `TimeFormat` and `ClockSettings`; state paths use `core/Paths.qml` and `home/hypr/.config/hypr/lib/state.lua`; a settings file is a `core/JsonStore.qml` child of its store singleton.

## Structure rules

Reviewers check Quickshell diffs against this section. Each rule names where it is enforced.

- Layers: a file imports its own layer or a lower one, in the order of `LAYERS` in `lib/check/steps/qml_layers.py` (`qml-layers`). `core/` imports nothing outside `core/`. A kept upward edge goes in `lib/check/qml-layers.allow`; delete the line in the PR that removes the edge.
- Imports: folders as `import qs.<path>`, JS relative (`import "Tints.js" as Tints`). `qml-layers` also fails a relative import from one feature or style into a sibling; go through a singleton (kept edges: `SIBLING_ALLOW`). `import qs.features.<y>` across features is unchecked.
- String-built paths and table-driven loads: `qml-paths` (`lib/check/steps/qml_paths.py`) lists the rules and the `// qs-path:` markers.
- Singleton names: see [Naming singletons](#naming-singletons).
- Where a new file goes (not checked): shared by several features and style-neutral, `ui/`; used by one feature, that feature's folder; one style's drawing, that feature if one uses it, else `styles/<name>/`. A single-style widget with three or more consumers (`MateriaOrb`, `VisorGlass`, `HandCursor`) lives in `ui/`.
- Greeter-staged files: any file the greeter loads is listed in `lib/common/greeter-files.sh`, edited in the PR that adds, moves or deletes it; ship-batch re-syncs the greeter from that list. A lock skin imports only files the greeter stages (not another skin, not `qs.services`).
- Tests: a check step's tests are `lib/check/tests/test_<step>.py`; a runtime QML test is `home/quickshell/tests/<name>/run.sh` with its own Step and `PATH_SCOPES` rule in `lib/check/scopes.py`. Run them through `lib/check.sh --only <step>` so the pass counts.
- Docs: `readme-links` (`lib/check/steps/readme_links.py`) fails a dead link, anchor or backticked path in a Quickshell README.

## Extending

**A Settings section.** Write `features/settings/sections/<Name>Section.qml`, usually a `RowsSection` with a list of rows, and add an entry to `list` in `features/settings/Sections.js`. The sidebar, search and IPC pick it up from there.

**A picker provider.** Subclass `features/launcher/PickerProvider.qml`: set `name` and `items`, implement `refresh()` and `activate()`, and it registers itself. Add it to `shell.qml` next to the other providers. To open it from Hyprland, bind `Menu.picker("<name>", "<rofi fallback>")` from `home/hypr/.config/hypr/lib/desktop/menu.lua`, so the bind still works without the bar. A provider that is mostly looked at rather than typed into can set `layout: "browse"` (search, a resizable preview, then a grid of cards, dropped from the center island) and supply its own `card`; see [launcher/README.md](features/launcher/README.md#browse-pickers).

Adding a [style or style token](theme/README.md#adding-a-style-or-style-token) and a [lock skin](features/lock/README.md#adding-a-lock-skin) is described next to the code they touch.

## Tools

Everything below is optional. A missing tool only disables the feature next to it. `hyprctl` (Hyprland) is required throughout. Tools for the bar, workspace overview and lock are in [Bar](features/bar/README.md#tools), [Workspace overview](features/overview/README.md#tools) and [Lock screen and greeter](features/lock/README.md#tools).

| Tool | Used for |
| --- | --- |
| `brightnessctl` | Screen and keyboard brightness sliders and keys |
| `cava` | Audio bars in the bar, lock screen and media popup |
| `checkupdates` (pacman-contrib), `paru` | The `updates` module's official and AUR counts |
| `grim`, `slurp`, `wf-recorder`, `wl-copy` | Screenshot and recording tools, copying the result |
| `cliphist`, `wl-copy` | The clipboard picker |
| `wtype`, `wl-copy` | The emoji picker |
| `zoxide` | The directories picker |
| `nmcli` (NetworkManager), `nm-connection-editor` | The network popup and its editor |
| `blueman-manager` | The Bluetooth module's manager |
| `pw-play` (PipeWire), `mpv` | Interface sounds, and lock and login music |
| `notify-send` | Error notices from the screenshot, usage and bar-layout checks |

The Nerd Font set in `theme/theme.json` draws every icon. `install.sh` installs Maple Mono NF (`lib/install/fonts.sh`) and the JetBrains and Symbols Nerd Fonts (`arch.ini`), and the shell logs a warning at startup when it is missing.

## Development

To try a worktree copy, stop the live bar (not while the screen is locked, the lock lives in it) and start the copy by path:

```bash
qs kill
hyprctl dispatch "hl.dsp.exec_cmd('qs -n -p $HOME/path/to/worktree/home/quickshell/.config/quickshell')"
```

Starting it through Hyprland rather than from a shell keeps the terminal's environment (tmux, say) out of everything the bar spawns. `qs-ipc` finds a bar started this way. Go back to the stowed config the same way with `qs -n`.

The live log is at `$XDG_RUNTIME_DIR/quickshell/by-id/<id>/log.log`, or read it with `qs log -p <path>` (`-f` to follow). A QML error there means the config didn't load. `qmllint` doesn't catch these reliably, so check the log after every change.

One rule for new code: nothing animates or polls on battery or while it isn't visible. Gate timers and animations on `PowerSource.on_ac` and on the item being shown.
