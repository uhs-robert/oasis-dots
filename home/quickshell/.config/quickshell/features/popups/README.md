# Popups

`popups/` holds the popup framework: `Popups` (which popup is open) and its IPC handler, the `Popup` base window with its title, keys, decor, key help, footer, title strip, style frames and `Slider` in `frames/`, `Tooltip` and `TooltipShelf`, `Confirm`, its IPC handler and `ConfirmPopup`, `LazyPopup`, `PopupScrim` and the `WhichKey` overlay.

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

A popup with only one level of views answers both `Tab` and `[`/`]`. In the clock popup, `Tab` and `[`/`]` cycle the time zones. `h`/`l` and `j`/`k` move the cursor by a day and a week, `Shift` + `h`/`l`/`j`/`k` by a month and a year; `Enter` opens the cursor day's events, `n`/`N` jump between days with events, `o` and `e` open Calendar and `c` creates an event (see [Clock and calendar](../clock/README.md)).

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
