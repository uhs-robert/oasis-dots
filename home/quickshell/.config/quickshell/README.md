# Quickshell

The desktop shell for this Hyprland setup, written for [Quickshell](https://quickshell.org). One config replaces Waybar, swaync, the rofi pickers, the lock screen and the greeter UI. Every monitor gets its own bar, and all colors follow the active Oasis theme (the GoldenEye style's Classic watch colours and its game iconography are the exception, see Styles).

Tested with Quickshell 0.3.1 (the `quickshell` package in the Arch repos); the installer warns if yours is older.

Hyprland starts it with `qs -n` (see `home/hypr/.config/hypr/config/autostart/`). Hyprland binds reach it over IPC. When it isn't running, the pickers fall back to rofi and the lock to hyprlock.

## Layout

| Path          | Purpose                                                                                    |
| ------------- | ------------------------------------------------------------------------------------------ |
| `shell.qml`   | Entry point: a bar per monitor, then every popup, picker provider, IPC handler and overlay |
| `bar/`        | The bar, its islands, the submap tab, the hot corner, and one file per module in `modules/` |
| `popups/`     | One popup per bar module (clock, volume, network, weather...), plus Start, Power and the screenshot tool |
| `picker/`     | The fuzzy picker, its providers (apps, clipboard, dirs, emoji, keybinds) and the HyprVim `:` prompt |
| `services/`   | Singletons that hold state (media, network, weather, notifications...) and the IPC handlers |
| `components/` | Shared widgets, with per-style pieces in their own folders (`nes/`, `ps1/`, `oasis/`...)   |
| `theme/`      | `Theme.qml` (colors from the Oasis theme) and `Style.qml` (every style's tokens)          |
| `settings/`   | The Settings panel and its sections                                                        |
| `lock/`       | The session lock, the simple lock screen and the styled lock skins in `skins/`             |
| `overview/`   | The workspace overview                                                                     |
| `fonts/`      | Bundled OFL fonts, registered for the whole shell                                          |
| `sounds/`     | UI sound packs                                                                             |
| `scripts/`    | Helpers the shell runs: greeter data, lock backdrop, audio importers, sound generator      |
| `assets/`     | Weather icons                                                                              |
| `bars.json`   | Tracked bar layout per monitor, matched by description or connector name                   |

Weather reads `weather.json`, with untracked per-machine overrides (real coordinates, say) in `weather.local.json`. With `latitude` and `longitude` set to `"auto"` the location comes from an IP lookup over HTTPS (ipwho.is), cached and repeated at most once a day.

## Bar layout

`bars.json` is a JSON array of rules. The first rule that matches a monitor decides its bar, and a monitor no rule matches gets no bar (the log says so). The tracked file ships one `"*"` rule. Edit it live, the bar reloads on save, and a broken file keeps the last good layout.

| Key | Meaning |
| --- | --- |
| `match` | `"*"` for every monitor, or `{ "name": "DP-*", "description": "*Dell*" }`. Both keys are optional globs (`*`, `?`) and must all match. `{}` or any string other than `"*"` never matches. `name` is the connector, `description` is Hyprland's monitor description (`hyprctl monitors`) |
| `compact` | Tighter bar that hides every `system` module. Defaults to true on `eDP*` connectors, false elsewhere |
| `height` | Bar height in pixels. Defaults to the style's bar height, else 34 |
| `bar` | `false` shows no bar on matching monitors |
| `left`, `center`, `right` | Module names, in draw order. Repeats within one list are dropped (a module in both `left` and `right` draws twice), unknown names are skipped with a warning. Lualine styles draw `center` inside the right island and re-sort it with `right` into their x/y/z sections, so the listed order only holds within a section |

Modules: `start` (Start button), `workspaces`, `clock` (calendar popup), `tray`, `volume`, `battery`, `bluetooth`, `network`, `weather`, `keeptabs` (AI agent sessions busy, done or waiting, jump to one; hidden while none run), `updates` (pending package updates), `voxtype` (dictation status), `recording` (screen recording chip), `notifications` (center and Do Not Disturb), `media` (now playing, not in the default layout) and `system`. `system` takes an argument, `system:cpu`, `system:memory` or `system:temperature`, and can be listed more than once with different arguments; bare `system` starts on `cpu`.

```json
[
  { "match": { "name": "eDP-*" }, "compact": true, "left": ["start", "workspaces"], "center": ["clock"], "right": ["volume", "battery"] },
  { "match": { "description": "*DELL U2720Q*" }, "height": 40, "left": ["start", "workspaces", "media"], "center": ["clock"], "right": ["tray", "network"] },
  { "match": "*", "left": ["start", "workspaces"], "center": ["clock"], "right": ["volume"] }
]
```

Settings > Bar modules edits the layout without touching the tracked file. It saves to `quickshell/bars.json` in the state folder (see Settings panel), with two kinds of override over the matching rule:

- `shared` applies to every monitor without its own layout. `place` maps a module to `left`, `center`, `right` or `hidden`, and `order` lists modules that swap among the slots they already fill on each side, and the rest do not move.
- `monitors` holds one full `left`/`center`/`right` layout (and `compact`) per monitor, keyed by `<description> @ <connector>`, or by the connector alone when the monitor has no description. After a connector change, the only saved key with the same description is reused. It replaces the rule's lists outright, so later edits to the tracked file no longer reach that monitor. `height` and `bar` always come from the rule.

Delete the state file to go back to the tracked layout.

## Styles

A style changes how the whole shell looks and behaves: fonts, frames, meters, key hints, transitions, sounds, even which views a popup shows. Colors never come from a style. They always come from the active Oasis palette, so every style works with every theme. The one deliberate exception is the game iconography of `goldeneye` (and its Classic mode), which keeps the pause watch's own colors under every palette (see below).

The styles, in picker order: `oasis` (the default), `modern`, `neovim`, `terminal`, `crt`, `nes`, `gameboy`, `snes`, `ps1`, `ff7`, `goldeneye`, `ps2`, `tie`, `halflife`, `metroid` and `reticle`. Everyday styles come first, then consoles by release year, then sci-fi.

Switch styles from Settings > Style (Start > Settings opens the panel), or over IPC:

```bash
qs ipc call style set ps1
qs ipc call style cycle
```

`goldeneye` is the GoldenEye 007 pause watch, drawn the same way as its lock skin. Popups are a frame around a translucent octagon panel, with highlight boxes and an `OASIS WATCH v<version>` readout (the version comes from the optional `VERSION` file at the config root). The bar workspaces are a watch strip with ticks (white on the focused one) and a pale hand, its minute ticks tinted along the bezel colors, on the bar's own background; the clock is DSEG7 digits on a dark panel; the weather header is the watch face with temperature and humidity segments; the clock popup shows an analogue watch face with the pale hands, which tick only on AC while the popup is open; the screenshot readouts are small watch faces. Settings > Theme options > Watch colours picks the mode. Theme (the default) tints the watch from your palette: the panel is the palette's surface and mantle backgrounds, text takes the primary's hue, frames use the palette background, and done, active and enabled states use its accent, info and highlights its secondary, errors and warnings its error and warning colors. Classic is the fixed green of the lock skin, from `theme/Watch.js`. In both modes the game iconography keeps its own colors: the red-to-yellow and blue arcs and meters, the white bars and studs, the pale clock hands and the red aiming crosshair. The lock skin follows the same option, taking its hue from the Lock screen > Tint setting in Theme mode, and the login screen follows it once synced to the greeter. Text outside the watch (bar labels) follows the palette.

Settings > Theme options tweaks the current style (scanlines, glow, dither, fonts, text size). The `gameboy` style also has a Model there: Color (the default, in the palette's own colors) or Original (four shades of the primary, grey shell). Settings > Colors picks the Oasis palette (right-clicking the Start button opens it too). It saves through `theme/switch.lua`, the same switcher the rofi fallback uses, which reloads Hyprland and reruns every color generator, including the one that writes `theme.json` for this shell to `~/.local/state/quickshell/` (or `$XDG_STATE_HOME`). The shell reads the palette from there first and falls back to `theme/theme.json` beside it, so a copy started with `qs -p` gets the current colors too.

## Settings panel

The panel drops from the center of the bar. Open it with `SUPER + SPACE` then `S`, from the Start menu, or with `qs ipc call settings open <section>` (section ids are in `settings/Sections.js`).

| Group        | Sections                           |
| ------------ | ---------------------------------- |
| Appearance   | Style, Colors, Theme options       |
| Bar          | Bar modules                        |
| System       | Displays, Default apps, Power      |
| Sound        | Theme audio                        |
| Lock & Login | Lock screen, Login screen          |

What you set here is saved as state under `~/.local/state` (or `$XDG_STATE_HOME`). State wins over the tracked defaults, so the repo stays clean while each machine keeps its own choices. Delete a file to fall back to the defaults.

| File                                      | Holds                                            |
| ----------------------------------------- | ------------------------------------------------ |
| `quickshell/style.json`                   | Current style, bar cava line                     |
| `quickshell/theme_options.json`           | Per-style option overrides                       |
| `quickshell/bars.json`                    | Bar module layout, merged over the tracked `bars.json` |
| `quickshell/hot_corners.json`             | Hot corners on or off                            |
| `quickshell/audio.json`                   | Theme audio choices                              |
| `quickshell/lock.json`                    | Lock skin, tint, backdrop, music                 |
| `quickshell/greeter.json`                 | Login screen choices                             |
| `quickshell/picker_usage.json`            | Picker ranking by use                            |
| `quickshell/timezones.json`               | Extra clock zones, a JSON array of IANA names    |
| `hypr/monitors.json`                      | Display settings, read by Hyprland               |
| `hypr/apps.json`                          | Default apps, read by Hyprland                   |
| `hypr/power.json`                         | Idle and power settings, read by Hyprland        |

The calendar clock cycles through the local zone plus any listed in `quickshell/timezones.json`, for example `["America/Los_Angeles", "America/Denver"]`; there is no Settings page for it.

Notification history lives in Quickshell's own per-config state folder (`~/.local/state/quickshell/by-shell/<id>/notifications.json`).

## Keys

Every popup uses the same keys. `?` shows the full list for the popup you're in.

| Key              | Action                                   |
| ---------------- | ---------------------------------------- |
| `[` / `]`        | Previous / next tab                      |
| `1`-`9`          | Jump to a tab                            |
| `Tab`            | Next sub-view (`Shift + Tab` back)       |
| `j` / `k`        | Move down / up                           |
| `h` / `l`        | Change a value, or move left / right     |
| `gg` / `G`       | First / last row                         |
| `/`              | Search, `n` / `N` for next / previous match |
| `Ctrl + h` / `l` | Walk to the neighbouring bar popup       |
| `Backspace`      | Back to the popup you came from          |
| `?`              | Key help                                 |
| `q` / `Esc`      | Close                                    |

Console styles draw controller buttons in place of keys in the footers and help.

The main binds that open things (the leader is `SUPER`):

| Bind                                  | Opens                                              |
| ------------------------------------- | -------------------------------------------------- |
| `SUPER + B`, then a letter            | A bar popup (`S` Start, `N` notifications, `V` volume, `W` weather, `C` calendar...) |
| `SUPER + SPACE`, then a letter        | The same popups, plus `S` Settings and `SPACE` Start |
| `SUPER + /`                           | Keybinds picker for the current submap             |
| `SUPER + O`                           | Apps picker                                        |
| `SUPER + T`                           | Workspace overview with window search (`SHIFT` carries the focused window to a workspace and follows it, `CTRL + SHIFT` leaves the view where it is) |
| `SUPER + CTRL + V`                    | Clipboard picker                                   |
| `SUPER + CTRL + SPACE`                | Directory picker                                   |
| `SUPER + CTRL + E`                    | Emoji picker                                       |
| `ALT + TAB`, `SUPER + TAB`            | Workspace overview (also the top-left hot corner)  |
| `Print`, `SUPER + I`                  | Screenshot and recording tool                      |
| `SUPER + [` / `]`                     | Focus the previous / next notification toast      |
| `SUPER + Q`, then `N`                 | Notification center                                |

All binds live in `home/hypr/.config/hypr/keymaps/`.

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
| `popup`         | `open <name>`, `toggle <name>`, `close`                               |
| `picker`        | `open <name>`, `open_with <name> <mode>`, `toggle <name>`, `close`    |
| `settings`      | `open <section>`, `toggle`                                            |
| `style`         | `set`, `cycle`, `get`, `set_lock`, `set_lock_tint`, `set_lock_backdrop`, `toggle_cava_line` and their getters |
| `overview`      | `open`, `close`, `toggle`, `search`, `move_follow`, `move_silent`                                           |
| `notifications` | `open`, `close`, `toggle_dnd`, `clear_all`, `dismiss_latest`, `dismiss_all`, `focus_toast`, `has_toast` |
| `screenshot`    | `open`, `close`, `toggle`, `select`, `pick`, `share`, `stop_recording` and the recording callbacks |
| `lock`          | `lock`, `state`, `preview <style>`, `preview_close`                   |
| `power`         | `confirm <lock\|logout\|reboot\|poweroff>`                            |
| `brightness`    | `refresh`                                                             |
| `transition`    | `play <kind or style>`                                                |
| `hyprvim_whichkey`, `hyprvim_prompt` | The HyprVim which-key HUD and `:` prompt          |

Popup names are the `LazyPopup` names in `shell.qml`: `start`, `settings`, `power`, `clock`, `volume`, `battery`, `bluetooth`, `system`, `tray`, `network`, `keeptabs`, `weather`, `updates`, `media`, `screenshot`, `notifications`.

## Lock screen and greeter

`~/.config/hypr/scripts/lock-screen.sh` (used by hypridle and the Power menu; hypridle passes `--auto`) locks with this shell and falls back to hyprlock when the bar isn't running or can't lock. If qs restarts while locked, the new instance takes the lock over.

Settings > Lock screen picks the lock: `follow` (the lock skin of the current style), `simple` (a plain card over a pixelated or blurred desktop), or any skin by name. Skins live in `lock/skins/` as `Crt`, `Ff7`, `Goldeneye`, `Mgs2`, `Ocarina` and `Tie`. `Ocarina` and `Mgs2` are lock-only and have no bar style. A style without a skin gets the simple screen. Tints recolor the skins (primary, secondary, green, amber, white). Once the password is accepted, any key skips the skin's unlock animation, on the lock and the login screen alike.

The FF7, GoldenEye, MGS2 and Ocarina skins can play game music and effects, which aren't in the repo. Import your own copies with `scripts/ff7-audio`, `scripts/goldeneye-audio`, `scripts/mgs2-audio` and `scripts/ocarina-audio`. Each takes the folder (or, for GoldenEye, the file) holding your copies as its argument. The MGS2 skin's effects are the exception: synthesized stand-ins ship in `lock/skins/mgs2/fx/` (from `scripts/synth-sounds mgs2-skin`), and an imported file of the same name replaces each one. The GoldenEye skin ships its lock and unlock chirps, the pause-watch static and typing, cursor, confirm, cancel and error clicks in `lock/skins/goldeneye/fx/` the same way (from `scripts/synth-sounds goldeneye-skin`, the clicks reusing the GoldenEye theme pack's).

These assets are gitignored and a skin without them stays silent (or skips its intro) rather than failing, so check the tools before importing. The audio importers write to `~/.local/share/quickshell/<skin>-audio/` and need `ffmpeg`, `python3` with `numpy`; all but `ff7-audio` also need `ffprobe` and `jq`; `goldeneye-audio` and `ocarina-audio` use `pipx` (for `pymusiclooper`) to detect loops unless you pass the loop points, and playback needs `mpv`. `goldeneye-frames` needs `ffmpeg`, `yt-dlp` and python with `PIL` and `numpy`. On Arch: `pacman -S ffmpeg jq python-numpy python-pillow python-pipx yt-dlp mpv`. Old in-tree FF7 imports in `lock/skins/ff7/audio/` keep playing until `~/.local/share/quickshell/ff7-audio/` has files.

The GoldenEye skin's intro and bezel are frames cut from gameplay footage, so they stay out of the repo: colour frames matted onto black with a mask sequence beside them, and the bezel plate. They live in `$XDG_DATA_HOME/quickshell/goldeneye-frames/` (`~/.local/share/quickshell/goldeneye-frames/` when unset), and the skin falls back to the gitignored `lock/skins/goldeneye/frames/` when the data dir has no `count.txt`. Without either the skin skips the intro and draws a plain bezel. Build them with `scripts/goldeneye-frames [VIDEO]` (needs ffmpeg and python with PIL and numpy). Without a file it uses `yt-dlp` to find the reference capture's stream and seeks straight to the 3 second intro and the 29 single frames the plate is taken from, so only those seconds are fetched (a few MB, not the whole hour). The greeter staging copies the data-dir frames into the greeter tree, since the greeter user has no data dir. On the lock, the intro and the unlock play over a screenshot of your desktop taken just before locking, which fades to black as the watch fills the screen (the login screen stays black). The lock takes that screenshot for this skin whatever Settings > Lock screen > backdrop says, and no screenshot is kept on screen once the intro is done. The header shows the version from an optional `VERSION` file at this config's root (`v0.0` without one), which the greeter staging copies too.

On the lock, all music (skin and theme) fades out after 2 minutes without a key press. A manual lock (keybind, Power menu, `lock-screen.sh`, `loginctl lock-session`) starts the music right away; an automatic one (idle timeout, before sleep, lid close) and a lock taken over after a bar restart stay silent until the first key press; the lock host owns this as `music_armed` on the lock ctx, so a skin with music gates on `ctx.music_armed !== false`. The login screen plays music from the start.

The login screen is a Quickshell greeter under greetd that shows your lock skin. The installer offers it; to update or install it by hand:

```bash
just greeter-sync            # stage it and print the sudo commands
just greeter-sync --install  # stage and install it
just greeter-preview         # try it in a window with a fake greetd
```

It installs to `/etc/greetd/quickshell` with its data in `/var/lib/qs-greeter`, which the bar keeps current as your theme and choices change (Settings > Login screen > Sync to greeter). `/usr/local/bin/qs-greeter` falls back to tuigreet when the greeter is missing, fails to start or crashes. Press `F10` or `SUPER + T` at the login screen to switch to tuigreet yourself.

## Extending

**A style.** Add its token set to `styles` in `theme/Style.qml` (most build on the shared `terminal` base with `Object.assign`), then add its name to `order`, and to `labels` if the label isn't just the capitalized name. Shared popup components take their palette colors from `Style.pal`, which defaults to the Oasis palette; a style can remap it (goldeneye does). Optional extras: a transition in `components/transitions/Kinds.js`, a sound pack in `sounds/<style>/` (a patch in `scripts/synth-sounds`) and a lock skin.

**A Settings section.** Write `settings/sections/<Name>Section.qml`, usually a `RowsSection` with a list of rows, and add an entry to `list` in `settings/Sections.js`. The sidebar, search and IPC pick it up from there.

**A picker provider.** Subclass `picker/PickerProvider.qml`: set `name` and `items`, implement `refresh()` and `activate()`, and it registers itself. Add it to `shell.qml` next to the other providers. To open it from Hyprland, bind `Menu.picker("<name>", "<rofi fallback>")` from `lib/actions/menu.lua`, so the bind still works without the bar.

**A lock skin.** Add `lock/skins/<Style>.qml` (first letter capitalized). It shows up in Settings > Lock screen and in the greeter once it exists. For a skin with no bar style, also add it to `lock_only` in `theme/Style.qml`. The greeter stages only `lock/skins/`, `lock/Tints.js`, `theme/` and `fonts/`, so a skin imports nothing from `components/` or `services/`; pieces a bar style shares with its skin (the GoldenEye watch colors, segment arcs and panel) live in the skin's own folder and the style imports them from there.

## Development

To try a worktree copy, stop the live bar (not while the screen is locked, the lock lives in it) and start the copy by path:

```bash
qs kill
hyprctl dispatch "hl.dsp.exec_cmd('qs -n -p $HOME/path/to/worktree/home/quickshell/.config/quickshell')"
```

Starting it through Hyprland rather than from a shell keeps the terminal's environment (tmux, say) out of everything the bar spawns. `qs-ipc` finds a bar started this way. Go back to the stowed config the same way with `qs -n`.

The live log is at `$XDG_RUNTIME_DIR/quickshell/by-id/<id>/log.log`, or read it with `qs log -p <path>` (`-f` to follow). A QML error there means the config didn't load. `qmllint` doesn't catch these reliably, so check the log after every change.

One rule for new code: nothing animates or polls on battery or while it isn't visible. Gate timers and animations on `Power.on_ac` and on the item being shown.

## Fonts and sounds

The bundled fonts are all under the SIL Open Font License. `fonts/README.md` lists each one with its source and licence file. The weather icons in `assets/weather/` are MIT licensed (see its `LICENSE`).

The sounds in `sounds/<style>/` are synthesized by `scripts/synth-sounds` (numpy and ffmpeg), one hand-built patch per style. `sounds/mgs2/` is an extra pack tied to no style. To use your own, drop `cursor`, `confirm`, `cancel`, `notify`, `error`, `lock` or `unlock` files (`.wav` or `.ogg`) into `~/.local/share/quickshell/sounds/<pack>/`, where `<pack>` is the style or pack name. They win file by file. [Custom sounds and music](../../../../docs/sounds.md) walks through it, along with lock music and the game lock screens' audio.

Settings > Audio picks one effects pack for every style: follow the style (the default), any style's sounds, the synthesized MGS2 pack, or an imported game pack (FFVII, MGS2, Ocarina). When following the style, FFVII uses the imported FFVII pack once there is one, and every other style its own. No music ships: lock and login music plays only from your own `music.ogg`, `music.wav` or `music.mp3` in `~/.local/share/quickshell/sounds/<style>/`.
