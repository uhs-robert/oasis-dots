# Bar

`bar/` holds the bar and its islands, the submap and voice-mode tabs, the hot corner, one file per module in `modules/`, `BarSettings` with `BarLayout.js` and `BarModules.js` (the layout and module registry), `LualineState`, `SubmapState`, the command-status state and IPC handler, the badged glyph and done/wait pulses the modules draw, and the neovim style's mode chip, buffer line, lualine sections and window segment in `neovim/`.

## Island fills

Every island fill (the base colour, shade, dither, scanlines and the lualine sections) goes through `Style.island_fill`, which applies Settings > Theme options > Island opacity; module content, borders, rims, insets and ticks do not. Below 100% (`Style.islands_translucent`) no pixel may be filled twice, because each fill fades on its own and stacked ones show darker. So `Island.qml` drops the 1px overlap between caps and body, and under lualine the island fills only behind modules that set no `lualine_fill` of their own, section c stops at the islands' caps, and the mode chip, buffers and sections draw each arrow as two colours side by side instead of one over the other. At 100% the overlapping opaque geometry, which hides fractional-scaling seams, is kept. A new fill follows the same rule.

## Bar layout

`bars.json` is a JSON array of rules. The first rule that matches a monitor decides its bar, and a monitor no rule matches gets no bar (the log says so). The tracked file ships one `"*"` rule. Edit it live, the bar reloads on save, and a broken file keeps the last good layout (if it is broken when the shell starts, there is no last good layout, so a minimal bar with workspaces, clock and tray shows and a notification names the error, until you save a valid file).

| Key | Meaning |
| --- | --- |
| `match` | `"*"` for every monitor, or `{ "name": "DP-*", "description": "*Dell*" }`. Both keys are optional globs (`*`, `?`) and must all match. `{}` or any string other than `"*"` never matches. `name` is the connector, `description` is Hyprland's monitor description (`hyprctl monitors`) |
| `compact` | Tighter bar that hides every `system` module. Defaults to false |
| `height` | Bar height in pixels. Defaults to the style's bar height, else 34 |
| `position` | Screen edge the bar sits on: `"top"` (default) or `"bottom"`. A bottom bar mirrors its islands' decoration and its popups, tooltips and submap tab rise from it; the OSD moves to the top and the hot corner to the bottom-left. `"left"` and `"right"` are reserved for vertical bars and fall back to top with a warning, as does any other value |
| `bar` | `false` shows no bar on matching monitors |
| `left`, `center`, `right` | Module names, in draw order. Repeats within one list are dropped (a module in both `left` and `right` draws twice), unknown names are skipped with a warning. Lualine styles draw `center` inside the right island and re-sort it with `right` into their x/y/z sections, so the listed order only holds within a section |

Modules (the registry is `features/bar/BarModules.js`): `start` (Start button), `workspaces`, `clock` (calendar popup), `tray`, `volume`, `battery`, `bluetooth`, `network`, `weather`, `keeptabs` (optional: needs the keeptabs tools in `~/.local/bin` and, for its usage tab, the `claude` CLI; shows AI agent sessions busy, done or waiting and jumps to one; hidden while none run or when keeptabs is not installed, and removable from `bars.json`), `cmdstatus` (status pills from your own commands, see Command status below; hidden without any), `updates` (pending package updates), `voxtype` (dictation status; its tooltip gives the exit hint while a voxcmd voice session is open), `recording` (screen recording chip), `notifications` (center and Do Not Disturb), `media` (now playing, not in the default layout) and `system`. `system` takes an argument, `system:cpu`, `system:memory` or `system:temperature`, and can be listed more than once with different arguments; bare `system` starts on `cpu`.

While a voxcmd voice session is open (`$XDG_RUNTIME_DIR/voxcmd/session.json`, ignored once its owner process is gone), the current mode (rapid, click, type...) hangs from the center island as a tab beside the Hyprland submap tab, tinted per mode `kind` from the theme's submap palette (`features/voice/VoxSessionState.qml`). Its text is the file's `label`; the `voxtype` tooltip shows its `exit_hint`.

While voxcmd's wake word listener holds the microphone (`$XDG_RUNTIME_DIR/voxcmd/wake.json` says `armed`; `voxcmd wake on` in the voxcmd README), the `voxtype` module shows a small dot beside its icon in the theme's secondary colour and its tooltip reads "Listening for \"Cortana\"" (`features/voice/VoxWakeState.qml`). It is deliberately not the recording pulse or colour: it shows only while voxtype is idle, and goes when the listener is off. While it is paused (`paused` in the file, with a `reason` naming the check that paused) and voxtype is idle, the dot stays but dimmed, and the tooltip says why: \"Wake word paused: another app is using the mic\" (`mic_in_use`), \"...: media is playing\" (`media_playing`) or \"...: a voice command is running\" (`voxtype_recording`, `session_open`); a missing or unknown reason reads \"Wake word paused\". When the file says `ready` (the listener's trigger started a recording and voxtype reports `recording`), the dot turns the theme's `ok` colour and blinks three times as the cue to speak, then clears with the recording.

```json
[
  { "match": { "name": "eDP-*" }, "compact": true, "left": ["start", "workspaces"], "center": ["clock"], "right": ["volume", "battery"] },
  { "match": { "description": "*DELL U2720Q*" }, "height": 40, "left": ["start", "workspaces", "media"], "center": ["clock"], "right": ["tray", "network"] },
  { "match": "*", "left": ["start", "workspaces"], "center": ["clock"], "right": ["volume"] }
]
```

Settings > Bar modules edits the layout without touching the tracked file. It saves to `quickshell/bars.json` in the state folder (see [Settings panel](../settings/README.md)), with three kinds of override over the matching rule:

- `shared` applies to every monitor without its own layout. `place` maps a module to `left`, `center`, `right` or `hidden`, and `order` lists modules that swap among the slots they already fill on each side, and the rest do not move. `position` (`top` or `bottom`, set by the Position row with All monitors as the target) is the global position: it applies to every monitor, own layout or not, and wins over the rule's `position`.
- `monitors` holds one full `left`/`center`/`right` layout (and `compact`) per monitor, keyed by `<description> @ <connector>`, or by the connector alone when the monitor has no description. After a connector change, the only saved key with the same description is reused. It replaces the rule's lists outright, so later edits to the tracked file no longer reach that monitor. `height` and `bar` always come from the rule.
- `positions` maps a monitor key (as in `monitors`) to `top` or `bottom`, set by the Position row with that monitor as the target and applied over the global position and the rule's `position`. It is kept apart from `monitors`, so a monitor needs no layout of its own to move its bar, and turning Own layout on or off leaves its position alone.

A bar's position is therefore the monitor's entry in `positions`, else `shared.position`, else the rule's `position`, else `top`. The Position row names what a value follows when it is not saved at that level, as in `bottom (global)`, `top (bars.json)` or `top (default)`; `x` on the row drops the saved value, so a monitor follows the global position again and All monitors follows `bars.json`.

Delete the state file to go back to the tracked layout.

## Command status

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

## Tools

Everything here is optional; a missing tool only disables the feature next to it.

| Tool | Used for |
| --- | --- |
| `keeptabs-status` (keeptabs) | The `keeptabs` module |
| `voxtype` | The `voxtype` module and dictation overlays |
