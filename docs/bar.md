# The bar

The bar is a strip of modules along one screen edge: workspaces, a clock, a tray, status icons and more. You choose which modules show and where, either in the bar editor or in a small JSON file, and you choose how the bar looks in Settings. This page covers both. The code behind it is in the [bar README](../home/quickshell/.config/quickshell/features/bar/README.md).

## Changing the layout

The fastest way is the bar editor. Open it from Settings > Bar modules > Edit bar, or run `qs ipc call bareditor open ""`. It covers every monitor that has a bar and works from the keyboard. Changes apply and save at once, and `?` lists the keys.

| Mode | Keys |
| --- | --- |
| Monitor select | `hjkl` pick a monitor by where it sits, Enter edits its bar, `q` or Esc closes |
| NORMAL | `h`/`l` select a module, Shift+`H`/`L` move it, `x` hide it, `c` compact it, `o` give this monitor its own layout, `u` undo, Ctrl+R redo, Tab shows the hidden modules, Shift+`V` selects the whole bar |
| HIDDEN (Tab) | `h`/`l` select a hidden module, Enter picks it up, `h`/`l` place it, Enter drops it |
| VISUAL (Shift+`V`) | `hjkl` move the whole bar to the left, bottom, top or right edge, `c` compact the whole bar |

`q` closes the editor from any mode. Hiding never deletes a module: Tab lists it so you can bring it back. Monitors share one layout until you press `o` on one, which gives it its own copy. Delete `bars.json` in the Quickshell state folder (`$XDG_STATE_HOME/quickshell/`) to go back to the shipped layout. The full key list and the code map are in the [bar editor README](../home/quickshell/.config/quickshell/features/bar_editor/README.md).

Settings > Bar modules also has Auto compact. It is on by default and makes a bar compact while its islands would overlap, then full again once they fit.

## The modules

| Module | Shows |
| --- | --- |
| `start` | The Start button |
| `workspaces` | The workspaces |
| `clock` | The time, with the calendar as a popup |
| `tray` | Tray icons |
| `volume`, `battery`, `bluetooth`, `network` | Status icons, each with a popup |
| `weather` | The weather |
| `updates` | Pending package updates |
| `keeptabs` | AI agent sessions that are busy, done or waiting (optional, hidden while none run) |
| `cmdstatus` | Status pills from your own commands, see below |
| `directory` | The focused app and, in a terminal, the program and its folder or file |
| `voxtype` | Dictation status |
| `recording` | The screen recording chip |
| `notifications` | The notification center and Do Not Disturb |
| `media` | The media well: album art, a play button, the title and artist, and a visualizer or the track position. Settings > Media sets it |
| `system` | CPU, memory or temperature as `system:cpu`, `system:memory` or `system:temperature`. List it more than once for more than one |

Most popups open after 300 ms of hover and pin on a click.

## bars.json

The shipped layout is the tracked `bars.json` in the Quickshell folder. It is a JSON array of rules. The first rule that matches a monitor decides its bar, and a monitor that no rule matches gets no bar. Edits apply on save, and a broken file keeps the last good layout.

```json
[
  { "match": { "name": "eDP-*" }, "compact": true, "left": ["start", "workspaces"], "center": ["clock"], "right": ["volume", "battery"] },
  { "match": "*", "left": ["start", "workspaces"], "center": ["clock"], "right": ["volume"] }
]
```

| Key | Meaning |
| --- | --- |
| `match` | `"*"` for every monitor, or an object with a `name` (the connector) and a `description` (as in `hyprctl monitors`), both optional globs |
| `compact` | A tighter bar. Only some modules have a compact form |
| `compact_modules` | Per-module override of `compact`, such as `{ "clock": false }` |
| `height` | Bar height in pixels |
| `position` | `"top"` (the default), `"bottom"`, `"left"` or `"right"` |
| `bar` | `false` shows no bar on matching monitors |
| `left`, `center`, `right` | Module names in draw order |

The bar editor does not touch this file. It saves its changes to `bars.json` in the state folder, over the matching rule. The [bar README](../home/quickshell/.config/quickshell/features/bar/README.md#bar-layout) lists every key the editor can save.

## Command status pills

The `cmdstatus` module puts the state of your own tools on the bar. Declare each one in `custom/command-status.json` in the Quickshell folder (gitignored, see the `custom/README.md` there). The module draws nothing until the file has an entry.

```json
[
  { "id": "timer", "command": "~/.local/bin/timer-status", "interval": 10, "on_click": "~/.local/bin/timer-toggle" }
]
```

| Key | Meaning |
| --- | --- |
| `id` | A unique name, used as the tooltip title and by IPC |
| `command` | A shell string or an argv array |
| `interval` | Seconds between runs, 30 by default. `0` runs once, then only on a click or a refresh |
| `on_click`, `on_right_click` | Optional commands for each click |

The command prints one line of JSON:

```json
{ "text": "1:24", "tooltip": "Running since 09:10", "class": "active", "hidden": false }
```

`class` is `idle`, `active`, `warn` or `error`. Anything else reads as `idle`. `hidden: true` drops the pill until the next run. A failed command shows an alert glyph with the error in its tooltip. To rerun an entry now, call `qs-ipc call cmdstatus refresh <id>`. A monitor with its own layout in the bar editor needs `cmdstatus` added there.

## Island shapes and fills

Each group of modules sits on an island. Settings > Theme options > Island shape picks the outline: slant, octagon, watch, window, rectangle, capsule, visor, chevron, lean, hex, ticket, tab, pixel or notch. None, underline and brackets draw no plate. Full bar draws one strip across the whole bar, and Floating strip sets that strip in from the screen edge. The row is not offered in a lualine bar (the NeoVim style), and a screen frame locks it to Full bar.

Island opacity, in the same section, sets how see-through the fill is. It applies to every shape that draws a plate. Each style starts with its own shape and opacity.

## Screen frame

Settings > Theme options > Screen frame draws bands round the screen's other edges, joined to the bar. Windows tile inside the hole they leave. It is off by default on every style. The Corner style row, on every style whether or not the frame is on, picks round, chamfer, pixel or square corners for the hole and for window rounding.

## Side bars

Set `position` to `"left"` or `"right"`, or pick the edge in the bar editor, and the bar becomes a column. Its islands stack top, center and bottom, and popups open beside it. In the editor, `j` and `k` also select modules on a side bar. Over a popup, Ctrl+K and Ctrl+J walk down a column where Ctrl+H and Ctrl+L walk along a row. The side-bar behavior is changing, so the [bar README](../home/quickshell/.config/quickshell/features/bar/README.md#side-bars) holds the current details.

## See also

- [Changing keybinds](keybinds.md)
- [Custom sounds and music](sounds.md)
- [Settings panel README](../home/quickshell/.config/quickshell/features/settings/README.md)
