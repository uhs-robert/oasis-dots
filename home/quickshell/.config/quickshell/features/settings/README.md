# Settings panel

`settings/` holds the Settings panel (`SettingsView`, its row and picker widgets, `Sections.js` and the `sections/`), `SettingsNav` and its IPC handler, and the settings services `DefaultAppsSettings`, `WallpaperSettings`, `HotCornersSettings` and `HyprInputSettings`.

Settings fills the focused monitor, in the same frame as the workspace overview: the section list on the left, the selected section in the middle and a help column on the right that explains the selected setting in full. It still answers to the popup system as `settings`, so it closes on a workspace switch and Ctrl+H/L do not walk to it. Open it with `SUPER + SPACE` then `S`, from the Start menu, or with `qs ipc call settings open <section>` (section ids are in `features/settings/Sections.js`).

The help column describes the selected (or hovered) setting and lists the keys that work on it. A section sets `description` and `description_keys` on `SettingsPane`; `RowsSection` fills them from a row's `desc`, optional `help` (a longer explanation shown after it) and optional `keys`, and a custom pane such as Bar modules does it for its own items.

| Group        | Sections                           |
| ------------ | ---------------------------------- |
| Appearance   | Style, Colors, Wallpaper, Theme options |
| Bar          | Bar modules, Clock, Calendar, Weather |
| System       | Displays, Default apps, Power      |
| Input        | Typing, Keyboard, Mouse & touchpad |
| Sound        | Theme audio                        |
| Lock & Login | Lock screen, Login screen          |

## Clock settings

Settings > Clock sets the time format and the calendar's first day of week. Time format is the locale's convention (the default), 12-hour or 24-hour, and every clock follows it: the bar clock in each style, the clock popup, weather hours and the Updates, Keeptabs and notification times. Lock-screen skins with a fixed game-style clock keep their own format. First day of week follows the locale (the default), or is Monday or Sunday. An old `time_format` in `weather.local.json` is carried over once and then removed. It saves to `clock.json` in the Quickshell state folder (`$XDG_STATE_HOME/quickshell/`, or `~/.local/state/quickshell/`).

## OSD edge

Settings > Style > OSD edge picks the edge the volume, brightness and voice OSD comes out of: opposite the bar (the default), the left edge or the right edge, the same on every monitor. On a side edge it sits centred, with the same panel as on top or bottom. It saves to `osd.json` in the Quickshell state folder.

## Input settings

Settings > Input > Typing picks the mode pickers, settings lists and type-to-search popups open in: INSERT (the default) to start typing at once, or NORMAL to start on the vim keys, where `i` or `/` starts typing. The HyprVim prompt always opens in INSERT, the clipboard's delete mode always in NORMAL, and the lock and greeter keep their own model. Remember last search refills each picker and settings list with its last query until the shell restarts. These save to `typing.json` in the Quickshell state folder (older versions called it `input.json`; the installer copies it). Which-key delay sets how long a leader key waits before its overlay shows; it is HyprVim's `which_key.delay_ms`, read once at setup, so changing it reloads Hyprland.

Settings > Input > Voice sets the "Cortana" listener (on or off now, and whether it starts at login: the same `systemctl --user start`/`stop` and `enable`/`disable` of `voxcmd-wake.service` that `voxcmd wake` makes), its sensitivity (Strict, Balanced or Relaxed; Custom when `VOXCMD_WAKE_THRESHOLD` or `_FRAMES` is set in the environment the units run with), whether it pauses while media plays (default keeps listening) and while another app is recording from a microphone (default pauses) and how much of its volume music keeps while voxtype records. The choices save to `voxcmd/voice.env` in the state folder (`KEY=VALUE` lines; see the voxcmd README), outside the stow-folded `~/.config/voxcmd`, and an environment variable of the same name still wins. The section reads that environment from systemd (the user manager's `set-environment` plus the `voxcmd-wake` and `voxtype` units' `Environment=`, not `EnvironmentFile=`), since the bar's own environment sees neither. After saving, a changed sensitivity or pause switch runs `systemctl --user try-restart voxcmd-wake` and a changed ducking `try-restart voxtype`, so only a unit that is running restarts (a voxtype restart cuts off a recording in progress).

Settings > Input > Keyboard and Mouse & touchpad set the XKB layout and variant, key repeat, pointer speed, focus follows mouse, natural scrolling, tap to click and disable while typing, plus Pointer keys (HJKL, WASD or both), which picks the keys that move the pointer in the Hyprland Cursor submap and reloads Hyprland. They save to `hypr/input.json` with the which-key delay, win over the machine profile's `input` values, and apply live through `config/input` in the Hyprland config. A row you have not changed shows Hyprland's current value. A saved `caps_escape` from an older version is ignored.

Keyboard also lists the remaps keyd applies below Hyprland, such as Caps Lock and Left Ctrl as Escape on tap and Ctrl on hold, and Tab as the vim layer on hold. They are read-only rows built at runtime from `/etc/keyd/default.conf` (installed from `system/etc/keyd/default.conf`), so they follow edits to it; Enter on the Tab row lists the vim layer's keys. They show only while the `keyd` service is active and the file is readable. To change a remap, edit that file and run `sudo keyd reload`; XKB options such as `caps:escape` do nothing for keys keyd has already remapped.

## Sessions settings

Settings > Sessions (System group) manages the layouts the launcher picker lists. Save current layout opens the overview in save mode: every window, regular and special, starts marked, `Space`/`v` and `V` unmark and mark, `Tab` switches between regular and special workspaces, and `Enter` asks for a name (prefilled with `Session N`). Nothing can be moved, closed or focused there, and `Esc` or `q` closes without saving. The windows are captured by the Hyprland side (`capture.lua`), written to `sessions.json` in the Hyprland state folder through `hypr/scripts/state-write`, and Settings opens on the new session. A saved session opens to its windows: rename it (`r`), replace its windows with the current ones (`u`, the same save mode, targeting that session), delete it (`x`), or open `sessions.json` in your Default apps editor inside your terminal (`e`, which closes Settings so the editor gets focus). `r`, `u` and `x` also work on a session's row in the list, and `x` on a window row removes that window; deleting or removing asks `y`/`n` first, like forgetting a network or Bluetooth device. A window row opens its placement (monitor and workspace, or a special workspace), command, launch delay and whether its size and position are kept. A command marked guessed was read from `/proc` and may need fixing, for example a single-instance terminal reports its server process. Lua sessions from `custom/sessions.lua` are listed read-only with a Lua marker, unless a saved session of the same name shadows them. The file is watched, so a hand edit in Neovim shows up at once; a file that does not parse blocks saving from Settings until fixed. `qs ipc call overview save_session ""` starts save mode directly, and a session name there replaces that session's windows.

## Wallpaper settings

Settings > Wallpaper drives the wallpaper rotator (`hypr/.config/hypr/extensions/wallpaper`). The top rows switch automatic rotation, the interval and the time-of-day, season and weather folders on or off, and `Enter` on Collection types a different wallpaper folder (empty goes back to the default); each connected monitor then cycles between Automatic and Pinned. `l` or `H`/`L` on a monitor row pins the image it shows now (or goes back to Automatic), `p` pins the image showing now or unpins a pinned monitor, `Enter` opens a searchable list of the collection with thumbnails to pin any image, filling the height of the section. `r` gives the selected monitor a new image, or every automatic monitor from the top rows (the same as `SUPER + Q` then `W`), and `o` closes Settings and opens the collection in the Default apps > Directories app; a terminal app such as yazi runs in your terminal. A monitor row shows one preview of its image, badged when it is the pin. It saves only what you change to `wallpaper.json` in the Hyprland state folder, pins keyed by monitor description, and reads what the rotator is actually using from its `wallpaper-status.json`. The rotator picks the file up within a few seconds; without it running the section says so.

## Saved state files

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
| `quickshell/clock.json`                   | Time format and first day of week                |
| `quickshell/osd.json`                     | The OSD's screen edge                            |
| `quickshell/typing.json`                  | Start mode for pickers and search popups         |
| `voxcmd/voice.env`                        | Voice choices (listener sensitivity, music ducking, type-mode pause), read by voxcmd, voxcmd-wake and voxtype-duck |
| `hypr/monitors.json`                      | Display settings, read by Hyprland               |
| `hypr/wallpaper.json`                     | Wallpaper rotation settings and per-monitor pins, read by the rotator |
| `hypr/wallpaper-status.json`              | What the rotator is doing, written by the rotator |
| `hypr/apps.json`                          | Default apps, read by Hyprland                   |
| `hypr/power.json`                         | Idle and power settings, read by Hyprland        |
| `hypr/sessions.json`                      | Saved sessions for the launcher picker, written by Settings > Sessions |
| `hypr/input.json`                         | Keyboard, mouse, touchpad, which-key delay and pointer keys, read by Hyprland |
