# Quickshell

The desktop shell for this Hyprland setup, written for [Quickshell](https://quickshell.org). One config replaces Waybar, swaync, the rofi pickers, the lock screen and the greeter UI. Every monitor gets its own bar, and all colors follow the active Oasis theme (the GoldenEye style's Classic watch colours and its game iconography are the exception, see Styles).

Tested with Quickshell 0.3.1 (the `quickshell` package in the Arch repos); the installer warns if yours is older.

Hyprland starts it with `qs -n` (see `home/hypr/.config/hypr/config/autostart/`). Hyprland binds reach it over IPC. When it isn't running, the pickers fall back to the menu in `Config.app.menu` (rofi by default; what fuzzel, wofi and other menus cover is in `home/hypr/.config/hypr/README.md`) and the lock to hyprlock.

## Layout

| Path          | Purpose                                                                                    |
| ------------- | ------------------------------------------------------------------------------------------ |
| `shell.qml`   | Entry point: a bar per monitor, then every popup, picker provider, IPC handler and overlay |
| `services/`   | Singletons that hold state (network...) and the IPC handlers |
| `ui/`         | Shared, style-neutral widgets: `menu/` (rows, tabs), `frames/` (brackets and the pieces a frame stack is built from), `gauges/` (`Meter`, `AtbBar`, `TickRuler`...), `keys/` (key badges and controller badges), `effects/` (dither, scanlines, sheen, sprites) |
| `styles/`     | One folder per style with the pieces that only that style draws: `tokens.js` (its token overrides), `icons.js` (its bar icon set, where it has one), `widgets/` and `sounds/` (the style's sound pack), and for snes `popups/`; `goldeneye/` also holds `Watch.js` (the watch colors), `watch_tokens.js` and the watch parts its lock skin shares (`PanelShape`, `SegmentArc`, `WatchHands`, `static.frag`). `index.js` builds every style's token set and `IconSets.js` registers the icon sets |
| `features/`   | One folder per feature (`features/<name>/`); `power/` holds `Power` (AC and battery state), its IPC handler and settings, the Power and Battery popups, and `PowerConfirm`; `clock/` holds `TimeFormat`, the clock and calendar settings, state and IPC, `Timezones`, the clock popup with its per-style status clocks in `views/`, and the meeting markers in `markers/`; `weather/` holds `WeatherState`, its IPC handler and fixtures, `Astro.js`, the weather popup, the oasis bar's `Horizon` sun arc, its icons in `icons/` and the per-style layouts in `views/` (see `views/README.md`); `launcher/` holds the fuzzy picker, its `Pickers` registry and IPC handler, its providers (apps, clipboard, dirs, emoji, keybinds, choices), the HyprVim `:` prompt in `hyprvim/`, and `InputSettings`; `screen_select/` holds `RegionSelector`, its toolbar and key overlays, and the `cursors/`, `loupe/` and `targets/` skins; `display/` holds `Displays` and `DisplayLayout.js` (monitor layout), `Backlight`, the brightness and zoom IPC handlers, and the overview zoom `Zoom` with its loupe and reticle; `media/` holds `MediaState` (MPRIS players), `CavaState` (the cava feed), the media popup with its album art, seek bar, round buttons and cava strip, and the volume popup; `osd/` holds the on-screen display for brightness, volume, power and voice state; `screenshot/` holds `Screenshot` (capture and recording state), its IPC handler, `ScreenShare` and the screenshot popup; `notifications/` holds `NotificationState` (history, toasts, Do Not Disturb), its IPC handler, `NotificationMarkup.js`, the notification center popup with its header button and cards, and the toasts with their card; `start/` holds the Start popup and its NES menu; `tray/` holds the system tray popup; `system/` holds the system popup and the `SysStats` and `SystemStat` singletons; `bluetooth/` holds the Bluetooth popup; `network/` holds the network popup with its Wi-Fi rows, header, details and password panes and `Network.js`; `keeptabs/` holds `KeeptabsState`, `ClaudeUsageState`, the keeptabs popup and its per-style Agents and Usage layouts in `views/`; `updates/` holds `UpdatesState` (pending package counts), the updates popup and its NES inventory; `overview/` holds the workspace overview (`Overview`, its frame, tiles, search list and aim overlays, `Voice.js` for the voice snapshot), the tmux overview (`TmuxOverview`, `TmuxTile`, `TmuxData.js`, `Ansi.js`), `WindowThumbnail` and the saved-session store (`SessionStore`, `SessionJson.js`); `bar/` holds the bar and its islands, the submap and voice-mode tabs, the hot corner, one file per module in `modules/`, `BarConfig` with `BarLayout.js` and `BarModules.js` (the layout and module registry), `LualineState`, `SubmapState`, the command-status state and IPC handler, the badged glyph and done/wait pulses the modules draw, and the neovim style's mode chip, buffer line, lualine sections and window segment in `neovim/`; `voice/` holds `VoxSession` and `VoxWake` (the voxcmd session and wake-word files), `VoxtypeState` and `VoxtypeAudio` (dictation state and samples), `VoiceSettings`, and the click hints: `ClickHints`, its IPC handler and `ClickHintsOverlay`; `settings/` holds the Settings panel (`SettingsPopup`, its row and picker widgets, `Sections.js` and the `sections/`), `SettingsNav` and its IPC handler, and the settings services `DefaultApps`, `WallpaperSettings`, `HotCorners` and `HyprInput`; `popups/` holds the popup framework: `Popups` (which popup is open) and its IPC handler, the `Popup` base window with its title, keys, decor, key help, footer, title strip, style frames and `Slider` in `frames/`, `Tooltip` and `TooltipShelf`, `Confirm`, its IPC handler and `ConfirmPopup`, `LazyPopup`, `PopupScrim` and the `WhichKey` overlay; `audio/` holds `ThemeAudio` (the sound packs and their volumes) and the `sound` IPC handler `SoundIpc`; `windows/` holds `WindowState` (Hyprland windows, most recently focused first); `lock/` holds the session lock (`Lock`, its IPC handler, preview and capture), the simple lock screen, the styled lock skins in `skins/`, the skin registry `LockSkins`, and the login screen's settings `LoginScreen` with `GreeterSync`, which keeps the greeter's data current |
| `core/`       | `Paths.qml` (XDG dirs), `JsonStore.qml` (one JSON settings file: debounced atomic save, watch, extras kept), `Fuzzy.js` (the fuzzy matcher), `RestartingStream.qml` (a streamed command restarted with backoff) and `PolledCommand.qml` (a command run on a timer or on demand, one result per run); imports nothing from the rest of the shell |
| `theme/`      | `Theme.qml` (colors from the Oasis theme), `Style.qml` (the active style's tokens), `StyleSchema.js` (every token's type, default and doc) and `BundledFonts.qml` (registers the bundled fonts) |
| `assets/fonts/` | Bundled OFL fonts, registered for the whole shell                                        |
| `sounds/`     | `alarm.ogg` and `mgs2/`, the sounds that belong to no style (each style's pack is in `styles/<style>/sounds/`) |
| `scripts/`    | Helpers the shell runs: greeter data, lock backdrop, audio importers, sound generator; `gen-style-exports` for `Style.qml` |
| `bars.json`   | Tracked bar layout per monitor, matched by description or connector name                   |

Settings > Calendar shows whether `calendar-sync` is connected and when it last synced. Enter offers Connect (or Reconnect), which opens your terminal on `calendar-sync setup`, and Sync now. The row asks `calendar-sync setup --check` once when the section opens, never on a timer, so a locked rbw or keyring shows as such without being prodded repeatedly.

Settings > Weather sets the location, units and forecast days. Automatic looks the place up from your IP address over HTTPS (ipwho.is), cached and repeated at most once a day; Manual takes a latitude, longitude and optional place name. Changes apply at once and are saved to `weather.local.json` (untracked) next to the tracked `weather.json` defaults, which it overrides. You can still edit either file by hand: `latitude` and `longitude` (a number or `"auto"`), `location_name` (replaces the looked-up name), `unit` (`fahrenheit` or `celsius`, which also picks mph or km/h and inches or mm), and `days` (1 to 16).

Weather alerts come from the US National Weather Service (api.weather.gov), so the Alerts tab only appears for US locations; elsewhere no alert request is made. When no forecast has loaded and the last fetch failed, the bar shows `n/a` and the tooltip and popup header give the reason; with data already loaded it keeps showing it as stale.

## Bar layout

`bars.json` is a JSON array of rules. The first rule that matches a monitor decides its bar, and a monitor no rule matches gets no bar (the log says so). The tracked file ships one `"*"` rule. Edit it live, the bar reloads on save, and a broken file keeps the last good layout (if it is broken when the shell starts, there is no last good layout, so a minimal bar with workspaces, clock and tray shows and a notification names the error, until you save a valid file).

| Key | Meaning |
| --- | --- |
| `match` | `"*"` for every monitor, or `{ "name": "DP-*", "description": "*Dell*" }`. Both keys are optional globs (`*`, `?`) and must all match. `{}` or any string other than `"*"` never matches. `name` is the connector, `description` is Hyprland's monitor description (`hyprctl monitors`) |
| `compact` | Tighter bar that hides every `system` module. Defaults to false |
| `height` | Bar height in pixels. Defaults to the style's bar height, else 34 |
| `bar` | `false` shows no bar on matching monitors |
| `left`, `center`, `right` | Module names, in draw order. Repeats within one list are dropped (a module in both `left` and `right` draws twice), unknown names are skipped with a warning. Lualine styles draw `center` inside the right island and re-sort it with `right` into their x/y/z sections, so the listed order only holds within a section |

Modules (the registry is `features/bar/BarModules.js`): `start` (Start button), `workspaces`, `clock` (calendar popup), `tray`, `volume`, `battery`, `bluetooth`, `network`, `weather`, `keeptabs` (optional: needs the keeptabs tools in `~/.local/bin` and, for its usage tab, the `claude` CLI; shows AI agent sessions busy, done or waiting and jumps to one; hidden while none run or when keeptabs is not installed, and removable from `bars.json`), `cmdstatus` (status pills from your own commands, see Command status below; hidden without any), `updates` (pending package updates), `voxtype` (dictation status; its tooltip gives the exit hint while a voxcmd voice session is open), `recording` (screen recording chip), `notifications` (center and Do Not Disturb), `media` (now playing, not in the default layout) and `system`. `system` takes an argument, `system:cpu`, `system:memory` or `system:temperature`, and can be listed more than once with different arguments; bare `system` starts on `cpu`.

While a voxcmd voice session is open (`$XDG_RUNTIME_DIR/voxcmd/session.json`, ignored once its owner process is gone), the current mode (rapid, click, type...) hangs from the center island as a tab beside the Hyprland submap tab, tinted per mode `kind` from the theme's submap palette (`features/voice/VoxSession.qml`). Its text is the file's `label`; the `voxtype` tooltip shows its `exit_hint`.

While voxcmd's wake word listener holds the microphone (`$XDG_RUNTIME_DIR/voxcmd/wake.json` says `armed`; `voxcmd wake on` in the voxcmd README), the `voxtype` module shows a small dot beside its icon in the theme's secondary colour and its tooltip reads "Listening for \"Cortana\"" (`features/voice/VoxWake.qml`). It is deliberately not the recording pulse or colour: it shows only while voxtype is idle, and goes when the listener is off. While it is paused (`paused` in the file, with a `reason` naming the check that paused) and voxtype is idle, the dot stays but dimmed, and the tooltip says why: \"Wake word paused: another app is using the mic\" (`mic_in_use`), \"...: media is playing\" (`media_playing`) or \"...: a voice command is running\" (`voxtype_recording`, `session_open`); a missing or unknown reason reads \"Wake word paused\". When the file says `ready` (the listener's trigger started a recording and voxtype reports `recording`), the dot turns the theme's `ok` colour and blinks three times as the cue to speak, then clears with the recording.

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

### Command status

The `cmdstatus` module shows a small pill per command you declare in `custom/command-status.json` (gitignored, see `custom/README.md`), so a machine-local tool can put its state on the bar without living in this repo. It sits after `workspaces` in the left island of the default layout and draws nothing until the file has an entry. A monitor with its own layout in Settings > Bar modules needs it added there.

```json
[
  { "id": "timer", "command": "~/.local/bin/timer-status", "interval": 10, "on_click": "~/.local/bin/timer-toggle", "on_right_click": ["xdg-open", "https://example.com"] }
]
```

| Key | Meaning |
| --- | ------- |
| `id` | Unique name; the tooltip title and the IPC handle |
| `command` | A string run through `sh -c` (so `~` and pipes work), or an argv array |
| `interval` | Seconds between runs (default 30). `0` runs once when the module appears, then only on a click or IPC refresh |
| `on_click`, `on_right_click` | Optional commands for left and right click; the status command reruns once they exit |

The command prints one line of JSON (the last line counts):

```json
{ "text": "1:24", "tooltip": "Running since 09:10", "class": "active", "hidden": false }
```

`class` is `idle` (bar text color), `active` (primary), `warn` or `error`, and anything else reads as `idle`. `hidden: true` drops the pill until the next run says otherwise. A non-zero exit or output that is not a JSON object shows an alert glyph in the error color, with the exit code and the last lines of stderr, or the parse error, in its tooltip. Text is plain, not markup.

Commands run asynchronously and only while a `cmdstatus` module is on a bar. A run still going when the next one is due is skipped, so a slow command never stacks up. The file is watched, so edits apply at once. After changing state from a script, `qs-ipc call cmdstatus refresh <id>` reruns that entry now instead of waiting for its interval.

## Styles

A style changes how the whole shell looks and behaves: fonts, frames, meters, key hints, transitions, sounds, even which views a popup shows. Colors never come from a style. They always come from the active Oasis palette, so every style works with every theme. The one deliberate exception is the game iconography of `goldeneye` (and its Classic mode), which keeps the pause watch's own colors under every palette (see below). The lock-only skins (`Mgs2`, `Ocarina`) are exempt as well: they draw their game's fixed palette and ignore the lock tint.

The styles, in picker order: `oasis` (the default), `modern`, `neovim`, `terminal`, `crt`, `nes`, `gameboy`, `snes`, `ps1`, `ff7`, `goldeneye`, `ps2`, `tie`, `halflife`, `metroid` and `reticle`. Everyday styles come first, then consoles by release year, then sci-fi.

Switch styles from Settings > Style (Start > Settings opens the panel), or over IPC:

```bash
qs ipc call style set ps1
qs ipc call style cycle
```

`goldeneye` is the GoldenEye 007 pause watch, drawn the same way as its lock skin. Popups are a frame around a translucent octagon panel, with highlight boxes and an `OASIS WATCH v<version>` readout (the version comes from the optional `VERSION` file at the config root). The bar workspaces are a watch strip with ticks (white on the focused one) and a pale hand, its minute ticks tinted along the bezel colors, on the bar's own background; the clock is DSEG7 digits on a dark panel; the weather header is the watch face with temperature and humidity segments; the clock popup shows an analogue watch face with the pale hands, which tick only on AC while the popup is open; the screenshot readouts are small watch faces. Settings > Theme options > Watch colours picks the mode. Theme (the default) tints the watch from your palette: the panel is the palette's surface and mantle backgrounds, text takes the primary's hue, frames use the palette background, and done, active and enabled states use its accent, info and highlights its secondary, errors and warnings its error and warning colors. Classic is the fixed green of the lock skin, from `styles/goldeneye/Watch.js`. In both modes the game iconography keeps its own colors: the red-to-yellow and blue arcs and meters, the white bars and studs, the pale clock hands and the red aiming crosshair. The lock skin follows the same option, taking its hue from the Lock screen > Tint setting in Theme mode, and the login screen follows it once synced to the greeter. Text outside the watch (bar labels) follows the palette.

Settings > Theme options tweaks the current style (scanlines, glow, dither, fonts, text size). `r` puts the selected option back to the style's own value and `R` resets every option of the style. Console styles also pick Controller glyphs there: All buttons, Labeled (face and menu buttons carry their key), D-pad (only directions and shoulders draw as buttons) or Off. The `gameboy` style also has a Model there: Color (the default, in the palette's own colors) or Original (four shades of the primary, grey shell). Every style also picks skins for several surfaces, each defaulting to the style's own and able to borrow any other style's, each named for what it draws with its style in brackets (Doors (Metroid)): Picker skin (the screenshot picker's cursor, magnifier and target list; Crosshair is the plain look), Overview skin (Night Vision adds the window counter, night-vision tint and lock-on crosshair, MGS1 Scope the aiming reticle), Workspaces (the bar's workspace indicator; Pills is the plain look under every style, round pills in its colors; the NES ? blocks and slime party, SNES world map, PSX tactics tiles and PS2 memory cubes can be borrowed too, and so can the pills of Modern as Dots, TIE as Diamonds and Half-Life as Squares), OSD layout (the volume and brightness OSD; Watch Dial also puts the dial header in the Volume and Battery popups), Weather layout (the weather popup's header with its Daily view; Watch, Battle, Scan Visor and HEV Suit bring their style's alert wording along), KeepTabs layout (the KeepTabs popup's Agents and Usage screens, each named for the game or tool it comes from, such as Party, Memory Card or htop; Plain is the shared list), Done animation and Waiting animation (the keeptabs module's celebration and waiting cue; Hearts and Bubble are the plain ones) and Toast arrival (Fade is the plain one). Borrowed skins draw in your palette, so the Game Boy shades, the GoldenEye watch ramp, the Materia colours and the hint keys fall back to it. Settings > Colors picks the Oasis palette (right-clicking the Start button opens it too). It saves through `theme/switch.lua`, the same switcher the rofi fallback uses, which reloads Hyprland and reruns every color generator, including the one that writes `theme.json` for this shell to `~/.local/state/quickshell/` (or `$XDG_STATE_HOME`). The shell reads the palette from there first and falls back to `theme/theme.json` beside it, so a copy started with `qs -p` gets the current colors too.

## Settings panel

The panel drops from the center of the bar. Open it with `SUPER + SPACE` then `S`, from the Start menu, or with `qs ipc call settings open <section>` (section ids are in `features/settings/Sections.js`).

Every section ends with a block that describes the selected (or hovered) setting in a line or two and lists the keys that work on it. A section sets `description` and `description_keys` on `SettingsPane`; `RowsSection` fills them from a row's `desc` and optional `keys`, and a custom pane such as Bar modules does it for its own items.

| Group        | Sections                           |
| ------------ | ---------------------------------- |
| Appearance   | Style, Colors, Wallpaper, Theme options |
| Bar          | Bar modules, Clock, Calendar, Weather |
| System       | Displays, Default apps, Power      |
| Input        | Typing, Keyboard, Mouse & touchpad |
| Sound        | Theme audio                        |
| Lock & Login | Lock screen, Login screen          |

### Calendar

The clock shows your Google Calendar from a cache that `calendar-sync` writes to `$XDG_CACHE_HOME/calendar/events.json` (default `~/.cache/calendar/`); the shell never talks to Google. With no cache file nothing changes: no countdown, no dots, no timer, and the popup has no dots or agenda. The service (`features/clock/CalendarState.qml`) reloads when the file changes, and `qs-ipc call calendar refresh` rereads it at once (a file that did not exist when the shell started is only noticed through that call or a restart). Cancelled events are ignored, and so are timed events over 12 hours for the chip and dot (out-of-office and conference blocks). The `join_url` field of an event holds a Google Meet or Microsoft Teams link. If `error.json` sits beside the cache, the events are the last good copy and the agenda header says so.

- Bar clock: within 15 minutes of the next meeting's start (even across midnight), a hollow dot and the minutes left (`12m`) follow the date; while a meeting is in progress the dot is solid. Hovering shows the current or next event and its time. All-day events never count as meetings.
- Clock popup: a dot under each day with events, and below the grid an agenda for the selected day (today by default). Event times follow the zone the popup is cycled to (as does the clock tooltip); events stay grouped by your local day.

The popup has two levels, both fully keyboard driven. At the grid level the cursor day's agenda is a read-only preview.

| Grid level | |
| --- | --- |
| `h` / `l`, `Left` / `Right` | Cursor day, back or forward one day (the shown month follows past its edge) |
| `j` / `k`, `Down` / `Up` | Cursor day, forward or back one week |
| `H` / `L`, `J` / `K` (Shift) | Month, then year; the cursor keeps its day of the month |
| `Enter` | Open day level for the cursor day (with a cache; an empty day shows "No events") |
| `n` / `N` | Jump the cursor to the next / previous day that has events, anywhere in the cache (does nothing past the last one) |
| `o` | Open the cursor day in Google Calendar's day view |
| `c` | Create an event on the cursor day |
| `t` / `gg` | Back to today |
| `Tab`, `[` `]` | Time zone |

| Day level | |
| --- | --- |
| `j` / `k`, `Down` / `Up` | Move between the day's events; the highlighted one is detailed below the list (time or "All day", title, location, organizer, guest count, "Tentative", and what Enter does) |
| `Enter` | Join the event's `join_url` (Google Meet or Teams), else open its Calendar page, else that day in Calendar |
| `Esc`, `h`, `Left` | Back to the grid, same day |
| `n` / `N` | Next / previous day with events; stays at day level and highlights that day's first open meeting |
| `o` / `e` | Open the highlighted event in Google Calendar to view it (its `event_url`) or to edit it (`.../r/eventedit/<eid>`, the `eid` taken from `event_url`); with no `eid` or no event both open that day's view |
| `c` | Create an event on that day: Google's form, in UTC, 9:00 to 10:00, or for today the next whole hour (9:00 tomorrow after 22:00) |
| `q` | Close |

Moving the cursor works without a calendar cache; the dots, the agenda and day level need one. Clicking a day equals moving to it and pressing Enter, and clicking an event highlights it, but nothing needs the mouse. `calendar open_day <date>` opens the popup at grid level on that date. The agenda area keeps one height across both levels and every day (the list shows eight rows at grid level and three beside the details at day level), so the popup never resizes.

When `events.json` carries `window_start` and `window_end` (the span calendar-sync fetched, end exclusive), days outside it are drawn faded and show "Not synced" instead of "No events", and `n`/`N` stay inside it; older caches without them dim nothing.

Links open with `firefox --new-tab`, or `xdg-open` when Firefox is not installed, and the script then focuses the Firefox window itself through `hyprctl`, since a launch without an activation token is not raised by Hyprland. Joining and creating share this path. Clicking a day selects it.

Settings > Clock sets the time format and the calendar's first day of week. Time format is the locale's convention (the default), 12-hour or 24-hour, and every clock follows it: the bar clock in each style, the clock popup, weather hours and the Updates, Keeptabs and notification times. Lock-screen skins with a fixed game-style clock keep their own format. First day of week follows the locale (the default), or is Monday or Sunday. An old `time_format` in `weather.local.json` is carried over once and then removed. It saves to `clock.json` in the Quickshell state folder (`$XDG_STATE_HOME/quickshell/`, or `~/.local/state/quickshell/`).

Settings > Input > Typing picks the mode pickers, settings lists and type-to-search popups open in: INSERT (the default) to start typing at once, or NORMAL to start on the vim keys, where `i` or `/` starts typing. The HyprVim prompt always opens in INSERT, the clipboard's delete mode always in NORMAL, and the lock and greeter keep their own model. Remember last search refills each picker and settings list with its last query until the shell restarts. These save to `typing.json` in the Quickshell state folder (older versions called it `input.json`; the installer copies it). Which-key delay sets how long a leader key waits before its overlay shows; it is HyprVim's `which_key.delay_ms`, read once at setup, so changing it reloads Hyprland.

Settings > Input > Voice sets the "Cortana" listener (on or off now, and whether it starts at login: the same `systemctl --user start`/`stop` and `enable`/`disable` of `voxcmd-wake.service` that `voxcmd wake` makes), its sensitivity (Strict, Balanced or Relaxed; Custom when `VOXCMD_WAKE_THRESHOLD` or `_FRAMES` is set in the environment the units run with), whether it pauses while media plays (default keeps listening) and while another app is recording from a microphone (default pauses) and how much of its volume music keeps while voxtype records. The choices save to `voxcmd/voice.env` in the state folder (`KEY=VALUE` lines; see the voxcmd README), outside the stow-folded `~/.config/voxcmd`, and an environment variable of the same name still wins. The section reads that environment from systemd (the user manager's `set-environment` plus the `voxcmd-wake` and `voxtype` units' `Environment=`, not `EnvironmentFile=`), since the bar's own environment sees neither. After saving, a changed sensitivity or pause switch runs `systemctl --user try-restart voxcmd-wake` and a changed ducking `try-restart voxtype`, so only a unit that is running restarts (a voxtype restart cuts off a recording in progress).

Settings > Input > Keyboard and Mouse & touchpad set the XKB layout and variant, key repeat, pointer speed, focus follows mouse, natural scrolling, tap to click and disable while typing, plus Pointer keys (HJKL, WASD or both), which picks the keys that move the pointer in the Hyprland Cursor submap and reloads Hyprland. They save to `hypr/input.json` with the which-key delay, win over the machine profile's `input` values, and apply live through `config/input` in the Hyprland config. A row you have not changed shows Hyprland's current value. A saved `caps_escape` from an older version is ignored.

Keyboard also lists the remaps keyd applies below Hyprland, such as Caps Lock and Left Ctrl as Escape on tap and Ctrl on hold, and Tab as the vim layer on hold. They are read-only rows built at runtime from `/etc/keyd/default.conf` (installed from `system/etc/keyd/default.conf`), so they follow edits to it; Enter on the Tab row lists the vim layer's keys. They show only while the `keyd` service is active and the file is readable. To change a remap, edit that file and run `sudo keyd reload`; XKB options such as `caps:escape` do nothing for keys keyd has already remapped.

Settings > Sessions (System group) manages the layouts the launcher picker lists. Save current layout opens the overview in save mode: every window, regular and special, starts marked, `Space`/`v` and `V` unmark and mark, `Tab` switches between regular and special workspaces, and `Enter` asks for a name (prefilled with `Session N`). Nothing can be moved, closed or focused there, and `Esc` or `q` closes without saving. The windows are captured by the Hyprland side (`capture.lua`), written to `sessions.json` in the Hyprland state folder through `hypr/scripts/state-write`, and Settings opens on the new session. A saved session opens to its windows: rename it (`r`), replace its windows with the current ones (`u`, the same save mode, targeting that session), delete it (`x`), or open `sessions.json` in your Default apps editor inside your terminal (`e`, which closes Settings so the editor gets focus). `r`, `u` and `x` also work on a session's row in the list, and `x` on a window row removes that window; deleting or removing asks `y`/`n` first, like forgetting a network or Bluetooth device. A window row opens its placement (monitor and workspace, or a special workspace), command, launch delay and whether its size and position are kept. A command marked guessed was read from `/proc` and may need fixing, for example a single-instance terminal reports its server process. Lua sessions from `custom/sessions.lua` are listed read-only with a Lua marker, unless a saved session of the same name shadows them. The file is watched, so a hand edit in Neovim shows up at once; a file that does not parse blocks saving from Settings until fixed. `qs ipc call overview save_session ""` starts save mode directly, and a session name there replaces that session's windows.

Settings > Wallpaper drives the wallpaper rotator (`hypr/.config/hypr/extensions/wallpaper`). The top rows switch automatic rotation, the interval and the time-of-day, season and weather folders on or off, and `Enter` on Collection types a different wallpaper folder (empty goes back to the default); each connected monitor then cycles between Automatic and Pinned. `l` or `H`/`L` on a monitor row pins the image it shows now (or goes back to Automatic), `p` pins the image showing now or unpins a pinned monitor, `Enter` opens a searchable list of the collection with thumbnails to pin any image, filling the height of the section. `r` gives the selected monitor a new image, or every automatic monitor from the top rows (the same as `SUPER + Q` then `W`), and `o` closes Settings and opens the collection in the Default apps > Directories app; a terminal app such as yazi runs in your terminal. A monitor row shows one preview of its image, badged when it is the pin. It saves only what you change to `wallpaper.json` in the Hyprland state folder, pins keyed by monitor description, and reads what the rotator is actually using from its `wallpaper-status.json`. The rotator picks the file up within a few seconds; without it running the section says so.

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
| `quickshell/typing.json`                  | Start mode for pickers and search popups         |
| `voxcmd/voice.env`                        | Voice choices (listener sensitivity, music ducking, type-mode pause), read by voxcmd, voxcmd-wake and voxtype-daemon |
| `hypr/monitors.json`                      | Display settings, read by Hyprland               |
| `hypr/wallpaper.json`                     | Wallpaper rotation settings and per-monitor pins, read by the rotator |
| `hypr/wallpaper-status.json`              | What the rotator is doing, written by the rotator |
| `hypr/apps.json`                          | Default apps, read by Hyprland                   |
| `hypr/power.json`                         | Idle and power settings, read by Hyprland        |
| `hypr/sessions.json`                      | Saved sessions for the launcher picker, written by Settings > Sessions |
| `hypr/input.json`                         | Keyboard, mouse, touchpad, which-key delay and pointer keys, read by Hyprland |

The calendar clock cycles through the local zone plus any listed in `quickshell/timezones.json`, for example `["America/Los_Angeles", "America/Denver"]`; there is no Settings page for it.

Notification history is kept in memory only (the last 100) and is gone when the shell restarts. The Do Not Disturb flag is saved as `{ "dnd": true }` in `notifications.json` in the Quickshell state folder (`$XDG_STATE_HOME/quickshell/`, default `~/.local/state/quickshell/`).

`qs-ipc call notifications history <count> <app>` prints that history as a JSON array, newest first: the newest `count` entries (`0` or less for all), only those from `app` when it is not `""`. Each entry is `get_last`'s fields plus the time it arrived, its urgency and whether the center has been opened since:

```json
[{"time": "2026-10-12T14:03:07.512Z", "app": "voxcmd", "summary": "voxcmd failed", "body": "Lock", "icon": "", "urgency": "normal", "read": false}]
```

Transient notifications (`notify-send --transient`) are shown as toasts but never kept, so the history holds only notifications sent without that hint; voxcmd, for one, sends only its errors that way. Notifications an app closes or replaces leave the history too.

## Keys

Every popup uses the same keys. `?` shows the full list for the popup you're in.

| Key              | Action                                   |
| ---------------- | ---------------------------------------- |
| `Tab` / `Shift + Tab` | Next / previous tab                 |
| `1`-`9`          | Jump to a tab                            |
| `[` / `]`        | Previous / next sub-view at the bottom   |
| `j` / `k`        | Move down / up                           |
| `h` / `l`        | Change a value, or move left / right     |
| `gg` / `G`       | First / last row                         |
| `/`              | Search, `n` / `N` for next / previous match |
| `Ctrl + h` / `l` | Walk to the neighbouring bar popup       |
| `Backspace`      | Back to the popup you came from          |
| `?`              | Key help                                 |
| `q` / `Esc`      | Close                                    |

A popup with only one level of views answers both `Tab` and `[`/`]`. In the clock popup, `Tab` and `[`/`]` cycle the time zones. `h`/`l` and `j`/`k` move the cursor by a day and a week, `Shift` + `h`/`l`/`j`/`k` by a month and a year; `Enter` opens the cursor day's events, `n`/`N` jump between days with events, `o` and `e` open Calendar and `c` creates an event (see Calendar).

Console styles draw controller buttons in place of keys in the footers and help. Each console is one entry in `ui/keys/KeyHints.js` (`controllers`): the path of its button component (`<console>/File.qml`, under `styles/<console>/widgets/`) and the key to button map. A button component is an `Item` with `button` (a name from the map), `size` and, for the Game Boy shades, `shades`.

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
| `SUPER + [` / `]`                     | Previous / next notification toast, else take the keyboard back for the open popup, else floating window |
| `ALT + GRAVE`                         | Tmux overview                                      |
| `SUPER + Z`                           | Zoom                                               |
| `SUPER + P`                           | Color picker                                       |
| `SUPER + U`                           | Restore the last closed window                     |
| `ALT + M`                             | Mute                                               |
| `SUPER + Q`, then `N`                 | Notification center                                |

All binds live in `home/hypr/.config/hypr/keymaps/`.

In the workspace overview, `[`/`]` cycle windows, `Tab`/`Shift + Tab` toggle the special workspaces, `s` picks a whole screen, `w` sends the selected workspace to a monitor (pick it like `s`, `Enter` confirms) and `W` swaps its windows with another workspace's (move to it, `Enter` confirms), and `f` toggles the view. Save mode (from Settings > Sessions) is the same overview with every window marked and no moving or closing. The share picker is the same overview with only shareable windows; there `r` opens the region selector, and Esc in it comes back.

## Workspace overview and voice

Voice drives the open overview through two things only: a snapshot file it publishes and one IPC entry, so voice and keys run the same functions. The voxcmd side is the Overview integration (`home/voxcmd/.config/voxcmd/README.md`).

- `$XDG_RUNTIME_DIR/voxcmd/overview.json`, rewritten (60 ms debounce) whenever the model, the marks or the mode change, and `{"version":1,"open":false}` while closed: `{version, open, special, marks: [address], monitors: [{id, slot, horizontal, vertical, focused}], items: [...]}`. A window item is `{n, kind: "window", id: address, label, workspace, monitor, marked}`, a workspace item `{n, kind: "workspace", id, label, workspace, monitor, marked: false, windows, shown}` (`id` and `workspace` are the id as a string, or `sp:<name>`). `n` for windows counts from 1 by monitor slot, workspace order and reading order; for workspaces it is the id (the position in hjkl order in the special view). `horizontal` (`left`, `middle`, `right`) and `vertical` (`top`, `middle`, `bottom`) come from the monitors' geometry (`features/overview/Voice.js`: rows by vertical position, then columns within a row) and are empty while there is one row or column to tell apart; `slot` is the `SUPER + CTRL + n` slot, 0 when unknown.
- `qs ipc call overview act <verb> "<args>"` returns `ok` or `error: <why>`. Window arguments are addresses; with none, `move`, `send` and `close` take the marks, or the selected window when nothing is marked, as `m` and `x` do. `mark`/`unmark <addr...>`, `clear`, `close [addr...]`, `focus <addr>` (closes the overview), `move <workspace> [addr...]`, `send <monitor> [addr...]` (to its visible workspace), `workspace <ref>` (focus, closes the overview), `workspace_to_monitor <id> <monitor>`, `swap_workspaces <ref> <ref>` (every window of one trades places with every window of the other) and `close_overview`.
- While voxcmd has a voice session of kind `overview` open (`VoxSession`), every window shows its `n` in a bordered badge at its bottom left, after a window glyph (nf-fa-window_maximize), and workspace chips read "WS n" (numeric names only). A marked window shows only its check badge at the top right while the numbers show, with no mark-order number.
- `w` and `W` call the same `move_workspace_to_monitor` and `swap_workspaces` the `act` verbs do.

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
| `popup`         | `open <name>`, `toggle <name>`, `close`, `focus`, `state`             |
| `picker`        | `open <name>`, `open_with <name> <mode>`, `toggle <name>`, `close`    |
| `settings`      | `open <section>`, `toggle`                                            |
| `style`         | `set`, `cycle`, `get`, `set_lock`, `set_lock_tint`, `set_lock_backdrop`, `toggle_cava_line` and their getters |
| `sound`         | `play <kind>`: a Theme audio sound if its category is on; `play alarm` always rings |
| `overview`      | `open`, `close`, `toggle`, `search`, `move_follow`, `move_silent`, `save_session <name>`, `state` (`open` or `closed`), `act <verb> <args>` (see Workspace overview and voice) |
| `tmux_overview` | `open`, `close`, `toggle`, `search`                                   |
| `notifications` | `open`, `close`, `toggle_dnd`, `get_dnd`, `get_last` (the newest history entry as JSON), `history <count> <app>` (see below), `clear_all`, `dismiss_latest`, `dismiss_all`, `focus_toast`, `has_toast` |
| `screenshot`    | `open`, `close`, `toggle`, `select`, `pick`, `share`, `stop_recording` and the recording callbacks |
| `zoom`          | `start`, `stop`, `toggle`, `step <delta>`, `size <delta>`, `full`     |
| `lock`          | `lock`, `lock_auto` (music waits for the first key), `state`, `preview <style>`, `preview_close` |
| `power`         | `confirm <lock\|logout\|reboot\|poweroff>`                            |
| `confirm`       | `ask <question> <result_path>`: drop the yes/no card from the center island; it writes `yes` or `no` to the path (No, Esc, the scrim and 10s without an answer are all `no`, the countdown waiting while voxtype records or transcribes); `dismiss <result_path>` closes that card without writing. `voxcmd-confirm` is the shell wrapper |
| `clickhints`    | `open <spec_path>`: numbered boxes over the screen from a JSON file `{label, choices: [{label, x, y, w, h}], result_path}` (global logical coordinates, at most ten); it writes the picked number, or an empty line for Esc, a click outside a box and 10s without an answer (the countdown waiting while voxtype records or transcribes), to the path, and returns `ok` (anything else means fall back to a text picker); `dismiss <result_path>` closes it without writing; `state` is `open` or `closed`. `voxcmd-hints` is the shell wrapper |
| `weather`       | `preview <fixture\|off>`, `previewing`: overlay a `features/weather/WeatherFixture.js` fixture on the live data (see Weather views) |
| `calendar`      | `refresh` (reread the calendar cache), `open_day <YYYY-MM-DD>` (open the clock popup on that day) |
| `brightness`    | `refresh`                                                             |
| `cmdstatus`     | `refresh <id>` (`""` refreshes every entry)                          |
| `transition`    | `play <kind or style>`                                                |
| `hyprvim_whichkey`, `hyprvim_prompt` | The HyprVim which-key HUD and `:` prompt          |

Popup names are the `LazyPopup` names in `shell.qml`: `start`, `settings`, `power`, `clock`, `volume`, `battery`, `bluetooth`, `system`, `tray`, `network`, `keeptabs`, `weather`, `updates`, `media`, `screenshot`, `notifications`, `picker`.

## Lock screen and greeter

`~/.config/hypr/scripts/lock-screen.sh` (used by hypridle and the Power menu; hypridle passes `--auto`) locks with this shell and falls back to hyprlock when the bar isn't running or can't lock. If qs restarts while locked, the new instance takes the lock over.

Settings > Lock screen picks the lock: `follow` (the lock skin of the current style), `simple` (a plain card over a pixelated or blurred desktop), or any skin by name. Skins live in `features/lock/skins/` as `Crt`, `Ff7`, `Goldeneye`, `Mgs2`, `Ocarina` and `Tie`. `Ocarina` and `Mgs2` are lock-only and have no bar style. A style without a skin gets the simple screen. Tints recolor the skins (primary, secondary, green, amber, white). Once the password is accepted, any key skips the skin's unlock animation, on the lock and the login screen alike. Skins with a game menu (`Ff7`, `Goldeneye`, `Mgs2`, `Ocarina`) offer Reboot and Shut down on the locked screen, each needing a second press to confirm; this is deliberate, so a locked machine can still be restarted. The `Mgs2` skin draws its menus in the system's Liberation Sans (`ttf-liberation`, in `packages/arch.ini`), so it falls back to the default font without it.

The FF7, GoldenEye, MGS2 and Ocarina skins can play game music and effects, which aren't in the repo. Import your own copies with `scripts/ff7-audio`, `scripts/goldeneye-audio`, `scripts/mgs2-audio` and `scripts/ocarina-audio`. Each takes the folder (or, for GoldenEye, the file) holding your copies as its argument. The MGS2 skin's effects are the exception: synthesized stand-ins ship in `features/lock/skins/mgs2/fx/` (from `scripts/synth-sounds mgs2-skin`), and an imported file of the same name replaces each one. The GoldenEye skin ships its lock and unlock chirps, the pause-watch static and typing, cursor, confirm, cancel and error clicks in `features/lock/skins/goldeneye/fx/` the same way (from `scripts/synth-sounds goldeneye-skin`, the clicks reusing the GoldenEye theme pack's).

These assets are gitignored and a skin without them stays silent (or skips its intro) rather than failing, so check the tools before importing. The audio importers write to `~/.local/share/quickshell/<skin>-audio/` and need `ffmpeg`, `python3` with `numpy`; all but `ff7-audio` also need `ffprobe` and `jq`; `goldeneye-audio` and `ocarina-audio` use `pipx` (for `pymusiclooper`) to detect loops unless you pass the loop points, and playback needs `mpv`. `goldeneye-frames` needs `ffmpeg`, `yt-dlp` and python with `PIL` and `numpy`. On Arch: `pacman -S ffmpeg jq python-numpy python-pillow python-pipx yt-dlp mpv`. Old in-tree FF7 imports in `features/lock/skins/ff7/audio/` keep playing until `~/.local/share/quickshell/ff7-audio/` has files.

The GoldenEye skin's intro and bezel are frames cut from gameplay footage, so they stay out of the repo: colour frames matted onto black with a mask sequence beside them, and the bezel plate. They live in `$XDG_DATA_HOME/quickshell/goldeneye-frames/` (`~/.local/share/quickshell/goldeneye-frames/` when unset), and the skin falls back to the gitignored `features/lock/skins/goldeneye/frames/` when the data dir has no positive `count.txt`. Without either the skin draws the bezel plate itself (`plate.frag`) and plays a low-poly Qt Quick 3D arm (`ArmIntro.qml`, needs `qt6-quick3d`) with the same timing; without Qt Quick 3D it skips the intro. Build them with `scripts/goldeneye-frames [VIDEO]` (needs ffmpeg and python with PIL and numpy). Without a file it uses `yt-dlp` to find the reference capture's stream and seeks straight to the 3 second intro and the 29 single frames the plate is taken from, so only those seconds are fetched (a few MB, not the whole hour). The greeter staging copies the data-dir frames into the greeter tree, since the greeter user has no data dir. On the lock, the intro and the unlock play over a screenshot of your desktop taken just before locking, which fades to black as the watch fills the screen (the login screen stays black). The lock takes that screenshot for this skin whatever Settings > Lock screen > backdrop says, and no screenshot is kept on screen once the intro is done. The header shows the version from an optional `VERSION` file at this config's root (`v0.0` without one), which the greeter staging copies too.

On the lock, all music (skin and theme) fades out after 2 minutes without a key press. A manual lock (keybind, Power menu, `lock-screen.sh`, `loginctl lock-session`) starts the music right away; an automatic one (idle timeout, before sleep, lid close) and a lock taken over after a bar restart stay silent until the first key press; the lock host owns this as `music_armed` on the lock ctx, so a skin with music gates on `ctx.music_armed !== false`. The login screen plays music from the start. It also starts at the desktop's output volume, which the sync carries over, because the greeter's audio server cannot remember one.

The login screen is a Quickshell greeter under greetd that shows your lock skin. The installer offers it; to update or install it by hand:

```bash
just greeter-sync            # stage it and print the sudo commands
just greeter-sync --install  # stage and install it
just greeter-preview         # try it in a window with a fake greetd
```

The Quickshell files it stages are listed once, in `lib/common/greeter-files.sh` (edit that list when one moves). `just greeter-sync --from DIR` stages the skins, theme files and fonts from another Quickshell config dir (for example a worktree's `home/quickshell/.config/quickshell`) instead of the repo's, and takes `DIR/theme/theme.json` over your saved theme when it has one. It installs to `/etc/greetd/quickshell` with its data in `/var/lib/qs-greeter`, which the bar keeps current as your theme and choices change (Settings > Login screen > Sync to greeter). `/usr/local/bin/qs-greeter` falls back to tuigreet when the greeter is missing, fails to start or crashes. Press `F10` or `SUPER + T` at the login screen to switch to tuigreet yourself.

## Extending

Folder imports are root-anchored, `import qs.<path>` (`import qs.theme`, `import qs.features.lock.skins as Skins`), so moving a file only renames the path; JS imports stay relative (`import "Tints.js" as Tints`).

**A style.** Add `styles/<name>/tokens.js` with an `overrides(t, ctx)` that returns the tokens it changes from the schema defaults (`t` is `Theme`), import it in `styles/index.js` and add it to the object `build()` returns there and to `sources` (the files Style.qml watches for hot reload), list it in `lib/common/greeter-files.sh` (the greeter stages each style's tokens), then add its name to `order` in `theme/Style.qml`, and to `labels` if the label isn't just the capitalized name. Shared popup components take their palette colors from `Style.pal`, which defaults to the Oasis palette; a style can remap it (goldeneye does). Its own widgets go in `styles/<name>/widgets/`; a `meter_art` or controller `button` token names one as `<name>/File.qml`. Optional extras: a transition in `theme/transitions/Kinds.js`, a sound pack in `styles/<name>/sounds/` (a patch in `scripts/synth-sounds`) and a lock skin.

**A style token.** Add one `tok(...)` line to `theme/StyleSchema.js` with its export type, default, a one-line doc and any options (`expr` for a computed export, `via: "bar"`, `export: false` for an internal key), then run `scripts/gen-style-exports` to rewrite the generated property lines in `Style.qml`. `just check` fails while they are out of date.

**A Settings section.** Write `features/settings/sections/<Name>Section.qml`, usually a `RowsSection` with a list of rows, and add an entry to `list` in `features/settings/Sections.js`. The sidebar, search and IPC pick it up from there.

**A picker provider.** Subclass `features/launcher/PickerProvider.qml`: set `name` and `items`, implement `refresh()` and `activate()`, and it registers itself. Add it to `shell.qml` next to the other providers. To open it from Hyprland, bind `Menu.picker("<name>", "<rofi fallback>")` from `lib/actions/menu.lua`, so the bind still works without the bar.

**A lock skin.** Add `features/lock/skins/<Style>.qml` (first letter capitalized). `features/lock/LockSkins.qml` is the only registry: it lists the folder, and the lock, the greeter staging, Settings and the thumbnails all resolve skins through it. The skin shows up in Settings > Lock screen and in the greeter once it exists. For a skin with no bar style, also add it to `features/lock/skins/index.json` with `lock_only` and a `label`; every skin has an entry there (fonts, `audio`, `own_music`). The greeter stages only the folders listed in `lib/common/greeter-files.sh`, so a skin imports nothing from any other (no `import qs.services`; `lib/check/steps/qml_paths.py` fails on it); pieces a bar style shares with its skin (the GoldenEye watch colors, segment arcs, panel, hands and static shader) live in `styles/goldeneye/`, and the greeter list stages each of them.

The skin contract:

- The root item has `property var ctx` (the `LockCtx`, set at load) and draws everything from it: auth state, `phase`, `buffer_length`, tint, clock and status. A skin never sees or stores the password and starts no processes beyond its own audio.
- Optional `readonly property int unlock_ms`: how long the unlock animation runs before the session opens (clamped to 0-4000 ms; 0 when absent).
- Optional `function handle_key(event)`: the shared router (`Lock.key`, `Greeter.key`) owns a vim-style mode, `ctx.insert`. In NORMAL mode (the default, and after a failed attempt or a relock) keys reach `handle_key` first, only while the password buffer is empty and nothing is pending; return exactly `true` to consume one. Skins may use `h`/`j`/`k`/`l` (matching their arrows), Enter, Space on a title screen, Escape and Tab for navigation, and every menu that moves with arrows should accept `h`/`j`/`k`/`l` too. `i` enters INSERT without typing anything, and any other printable key the skin leaves alone enters INSERT and is typed as the first password character, so a skin must return `false` for those (it may step its own scene, e.g. to a password screen). In INSERT mode, or while the buffer is non-empty or a check runs, skins get no keys and every printable key goes to the password; Escape on an empty buffer returns to NORMAL (and is then offered to the skin). A password starting with `i` therefore needs the key twice. A skin must not take keyboard focus: the lock and greeter hold it so a broken skin still takes the password.
- Optional mode indicator: the shared layer draws `-- INSERT --` bottom-left only in INSERT mode, in `mode_color` (default the lock tint) and `mode_font` (default the shell mono font) when the skin sets them. Set `readonly property string mode_indicator` to `"own"` (the skin draws it from `ctx.insert`) or `"none"` to hide the shared one; the default is `"shared"`.
- Optional audio: play only when `ctx.sound` is set and the skin is the `ctx.sound_owner`, gate music on `ctx.music_armed !== false`, send effects with `ctx.cue(name)`, and let `ctx.power_request` only ask, since only a `power_live` ctx acts on it. Imported audio lives in `$XDG_DATA_HOME/quickshell/<skin>-audio`; assets inside the skin's folder are staged with it.
- Honour `ctx.animate` (loops stop off AC) and `ctx.saver`.


## Tools

Everything below is optional. A missing tool only disables the feature next to it. `hyprctl` (Hyprland) is required throughout.

| Tool | Used for |
| --- | --- |
| `brightnessctl` | Screen and keyboard brightness sliders and keys |
| `cava` | Audio bars in the bar, lock screen and media popup |
| `checkupdates` (pacman-contrib), `paru` | The `updates` module's official and AUR counts |
| `keeptabs-status` (keeptabs) | The `keeptabs` module |
| `voxtype` | The `voxtype` module and dictation overlays |
| `grim`, `slurp`, `wf-recorder`, `wl-copy` | Screenshot and recording tools, copying the result |
| `cliphist`, `wl-copy` | The clipboard picker |
| `wtype`, `wl-copy` | The emoji picker |
| `zoxide` | The directories picker |
| `tmux` | The tmux overview and the tmux targets picker |
| `nmcli` (NetworkManager), `nm-connection-editor` | The network popup and its editor |
| `blueman-manager` | The Bluetooth module's manager |
| `pw-play` (PipeWire), `mpv` | Interface sounds, and lock and login music |
| `jq` | Staging the login screen (`just greeter-sync`) |
| `notify-send` | Error notices from the screenshot, usage and bar-layout checks |
| `ffmpeg` | The audio and frame import scripts in `scripts/` |

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

## Weather views

Each style draws its own popup layout in `features/weather/views/<token>/`; `views/README.md` maps tokens to styles.

Test data lives in `features/weather/WeatherFixture.js` (`base`, `alerts1`, `alerts3`, `aqi-bad`, `rain`, `night`), shaped like the data `WeatherState` builds.

To see a fixture in the live popup, `qs-ipc call weather preview alerts3` (then open the popup), `qs-ipc call weather previewing`, and `qs-ipc call weather preview off`. While a preview is on, weather fetches are paused; `off` restores the real data and refetches.

## Fonts and sounds

The bundled fonts are all under the SIL Open Font License. `assets/fonts/README.md` lists each one with its source and licence file. The weather icons in `features/weather/icons/` are MIT licensed (see its `LICENSE`).

The sounds in `styles/<style>/sounds/` are synthesized by `scripts/synth-sounds` (numpy and ffmpeg), one hand-built patch per style. `sounds/mgs2/` is an extra pack tied to no style. `sounds/alarm.ogg`, a digital watch beep from the same script, is the alarm for a style with no pack and for Theme audio with interface and notification sounds both off. To use your own, drop `cursor`, `confirm`, `cancel`, `notify`, `error`, `lock`, `unlock` or `alarm` files (`.wav` or `.ogg`) into `~/.local/share/quickshell/sounds/<pack>/`, where `<pack>` is the style or pack name. They win file by file. [Custom sounds and music](../../../../docs/sounds.md) walks through it, along with lock music and the game lock screens' audio.

Settings > Theme audio (in the Sound group) picks one effects pack for every style: follow the style (the default), any style's sounds, the synthesized MGS2 pack, or an imported game pack (FFVII, MGS2, Ocarina). When following the style, FFVII uses the imported FFVII pack once there is one, and every other style its own. No music ships: lock and login music plays only from your own `music.ogg`, `music.wav` or `music.mp3` in `~/.local/share/quickshell/sounds/<style>/`.
