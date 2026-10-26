# Quickshell

The desktop shell for this Hyprland setup, written for [Quickshell](https://quickshell.org). One config replaces Waybar, swaync, the rofi pickers, the lock screen and the greeter UI. Every monitor gets its own bar, and all colors follow the active Oasis theme (the GoldenEye style's Classic watch colours and its game iconography are the exception, see [Styles](theme/README.md#styles)).

Tested with Quickshell 0.3.1 (the `quickshell` package in the Arch repos); the installer warns if yours is older.

Hyprland starts it with `qs -n` (see `home/hypr/.config/hypr/config/autostart/`). Hyprland binds reach it over IPC. When it isn't running, the pickers fall back to the menu in `Config.app.menu` (rofi by default; what fuzzel, wofi and other menus cover is in `home/hypr/.config/hypr/README.md`) and the lock to hyprlock.

## Layout

| Path          | Purpose                                                                                    |
| ------------- | ------------------------------------------------------------------------------------------ |
| `shell.qml`   | Entry point: a bar per monitor, then every popup, picker provider, IPC handler and overlay |
| `services/`   | `Palettes`, the one singleton not yet moved into a feature (`shell.qml` still imports it so Quickshell registers the module) |
| `ui/`         | Shared widgets: `menu/` (rows, tabs), `frames/` (brackets and the pieces a frame stack is built from), `gauges/` (`Meter`, `AtbBar`, `TickRuler`...), `keys/` (key badges and controller badges), `effects/` (dither, scanlines, sheen, sprites) |
| `styles/`     | One folder per style with the pieces that only that style draws: `tokens.js` (its token overrides), `icons.js` (its bar icon set, where it has one), `widgets/` and `sounds/` (the style's sound pack), and for snes `popups/`; `goldeneye/` also holds `Watch.js` (the watch colors), `watch_tokens.js` and the watch parts its lock skin shares (`PanelShape`, `SegmentArc`, `WatchHands`, `static.frag`). `index.js` builds every style's token set and `IconSets.js` registers the icon sets |
| `features/`   | One folder per feature, listed under Features below |
| `core/`       | `Paths.qml` (XDG dirs), `JsonStore.qml` (one JSON settings file: debounced atomic save, watch, extras kept; or with `read_only` a follower of a file another program writes), `Fuzzy.js` (the fuzzy matcher), `RestartingStream.qml` (a streamed command restarted with backoff, re-probed for its tool, planned exits not counted as failures), `PolledCommand.qml` (a command run on a timer or on demand, one result per run) and `PolledFile.qml` (a file read on a timer or on demand, `loaded` or `load_failed` per read) |
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
- `launcher/` holds the fuzzy picker, its `Pickers` registry and IPC handler, its providers (apps, clipboard, dirs, emoji, keybinds, choices), the HyprVim `:` prompt in `hyprvim/`, and `TypingSettings`.
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
- `keeptabs/` holds `KeeptabsState`, `ClaudeUsageState`, the keeptabs popup and its per-style Agents and Usage layouts in `views/`.
- `updates/` holds `UpdatesState` (pending package counts), the updates popup and its NES inventory.
- [`overview/`](features/overview/README.md): Workspace overview, voice contract and tmux tools
- [`bar/`](features/bar/README.md): Bar layout and modules, command status
- `voice/` holds `VoxSessionState` and `VoxWakeState` (the voxcmd session and wake-word files), `VoxtypeState` and `VoxtypeAudioState` (dictation state and samples), `VoiceSettings`, and the click hints: `ClickHints`, its IPC handler and `ClickHintsOverlay`.
- [`settings/`](features/settings/README.md): The Settings panel and its saved state files
- [`popups/`](features/popups/README.md): Popup framework and shared popup keys
- `audio/` holds `ThemeAudio` (the sound packs and their volumes) and the `sound` IPC handler `SoundIpc`.
- `style/` holds `StyleIpc`, the `style` IPC handler (style, lock skin and sound-pack calls).
- `windows/` holds `WindowState` (Hyprland windows, most recently focused first).
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

| Target          | Functions                                                             |
| --------------- | --------------------------------------------------------------------- |
| `popup`         | `open <name>`, `toggle <name>`, `close`, `focus`, `keyboard`, `state` |
| `picker`        | `open <name>`, `open_with <name> <mode>`, `toggle <name>`, `close`    |
| `settings`      | `open <section>`, `toggle`, `view <section> <screen>`, `cursor <index>`, `step <delta>`, `activate`, `back`, `hide` |
| `style`         | `set`, `cycle`, `get`, `set_lock`, `set_lock_tint`, `set_lock_backdrop`, `toggle_cava_line` and their getters |
| `sound`         | `play <kind>`: a Theme audio sound if its category is on; `play alarm` always rings |
| `overview`      | `open`, `close`, `toggle`, `search`, `move_follow`, `move_silent`, `save_session <name>`, `state` (`open` or `closed`), `act <verb> <args>` (see [Workspace overview and voice](features/overview/README.md)) |
| `tmux_overview` | `open`, `close`, `toggle`, `search`, `state`                          |
| `osd`           | `state`                                                               |
| `notifications` | `open`, `close`, `toggle_dnd`, `get_dnd`, `get_last` (the newest history entry as JSON), `history <count> <app>` (see [Notifications](features/notifications/README.md)), `clear_all`, `dismiss_latest`, `dismiss_all`, `focus_toast`, `has_toast` |
| `screenshot`    | `open`, `close`, `toggle`, `select`, `pick`, `share`, `stop_recording` and the recording callbacks |
| `zoom`          | `start`, `stop`, `toggle`, `step <delta>`, `size <delta>`, `full`     |
| `lock`          | `lock`, `lock_auto` (music waits for the first key), `state`, `preview <style>`, `preview_close` |
| `power`         | `confirm <lock\|logout\|reboot\|poweroff>`, `run <action>`            |
| `confirm`       | `ask <question> <result_path>`: drop the yes/no card from the center island; it writes `yes` or `no` to the path (No, Esc, the scrim and 10s without an answer are all `no`, the countdown waiting while voxtype records or transcribes); `dismiss <result_path>` closes that card without writing. `voxcmd ask confirm` is the shell caller |
| `clickhints`    | `open <spec_path>`: numbered boxes over the screen from a JSON file `{label, choices: [{label, x, y, w, h}], result_path}` (global logical coordinates, at most ten); it writes the picked number, or an empty line for Esc, a click outside a box and 10s without an answer (the countdown waiting while voxtype records or transcribes), to the path, and returns `ok` (anything else means fall back to a text picker); `dismiss <result_path>` closes it without writing; `state` is `open` or `closed`. `voxcmd-hints` is the shell wrapper |
| `weather`       | `preview <fixture\|off>`, `previewing`: overlay a `features/weather/WeatherFixture.js` fixture on the live data (see [Weather views](features/weather/README.md)) |
| `calendar`      | `refresh` (reread the calendar cache), `open_day <YYYY-MM-DD>` (open the clock popup on that day) |
| `brightness`    | `refresh`                                                             |
| `cmdstatus`     | `refresh <id>` (`""` refreshes every entry)                          |
| `transition`    | `play <kind or style>`                                                |
| `hyprvim_whichkey`, `hyprvim_prompt` | External API: the HyprVim which-key HUD and `:` prompt, each with `open` and `close`, called by the hyprvim plugin |

Popup names are the `LazyPopup` names in `shell.qml`: `start`, `settings`, `power`, `clock`, `volume`, `battery`, `bluetooth`, `system`, `tray`, `network`, `keeptabs`, `weather`, `updates`, `media`, `screenshot`, `notifications`, `picker`.

## Naming singletons

A singleton is named for what it holds: `Settings` for the user's saved choices (`ClockSettings`, `BarSettings`), `State` for live data read from outside (the system, a daemon, a file the user does not edit), and otherwise a plain noun for what it is (`Sessions`, `Popups`). A name ending in `Config`, `Store` or `Manager` says which of those it is only by accident, so `lib/check/steps/qml_singleton_names.py` fails any `pragma Singleton` file named that way unless `lib/check/qml-singleton-names.allow` lists it as a temporary exception; the rename that removes the name deletes the line.

## Extending

Structure rules (layers, imports, where a new file goes, greeter-staged files, tests) are in [AGENTS.md](../../../../AGENTS.md#quickshell-structure).

**A Settings section.** Write `features/settings/sections/<Name>Section.qml`, usually a `RowsSection` with a list of rows, and add an entry to `list` in `features/settings/Sections.js`. The sidebar, search and IPC pick it up from there.

**A picker provider.** Subclass `features/launcher/PickerProvider.qml`: set `name` and `items`, implement `refresh()` and `activate()`, and it registers itself. Add it to `shell.qml` next to the other providers. To open it from Hyprland, bind `Menu.picker("<name>", "<rofi fallback>")` from `home/hypr/.config/hypr/lib/actions/menu.lua`, so the bind still works without the bar.

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
