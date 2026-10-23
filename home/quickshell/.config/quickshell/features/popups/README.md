# Popups

`popups/` holds the popup framework: `Popups` (which popup is open) and its IPC handler, the `Popup` base window with its title, keys, decor, key help, footer, title strip, style frames and `Slider` in `frames/`, `Tooltip` and `TooltipShelf`, `Confirm`, its IPC handler and `ConfirmPopup`, `LazyPopup`, `PopupScrim` and the `WhichKey` overlay.

## Frame drawers

With the screen frame on (`features/bar/README.md`, "Drawers"), a bar-hung popup is a drawer instead of a hung panel: `Popup.qml` places its window against the frame's seam (ignoring the exclusive zones), draws it with `DrawerShape` in the frame's material, and slides the body out of the seam with the content riding along. A centre popup has a fillet at each end; a left or right island's popup has a pocket against that side band. The accent line, drop shadow and the style's own panel fill and border give way; the title, LCD and other inner decor stay, and dither and scanlines are off. With translucent islands the drawer takes their opacity too: it fills only the hole, and the frame and the bar's strip leave their rim and inset line out under the drawer's window (`ScreenFrames.drawer_windows`, drawn round it by `GapClip`) so the join is one fill, not two stacked. A drawer in a style with the handheld shell keeps its rim and inset line only along the mouth and fillets, not round the body. The gameboy handheld shell inside a drawer is interim: it still covers the rim and its rounded top corners leave notches at the mouth, until the gameboy drawer look is decided from screenshots. Clicks outside the visible body, fillet corners included, pass through. `settled` and `closing` keep their meaning: the slide is the same `drop_progress` run, and the accent-line step takes no time. A docked popup (`dock_bottom`: the picker opened without an island, and the hyprvim prompt) is a drawer on the bottom edge: it hangs from the bottom bar's strip seam, or the bottom band without one, with a pocket at both ends and the whole hole as its width. Passive tooltips are not drawers yet, and with the frame off nothing changes.

The which-key HUD (`WhichKey.qml`) is a drawer too, from the edge its payload `position` names: `top-*` hangs from the top seam (the bar strip under a top bar), `bottom-*` from the bottom one; `*-left` and `*-right` pocket against that side band and fillet at the other end, `*-center` fillets at both. A plain `center` has no edge and stays floating, as does any monitor without the frame. It grows out on show (190 ms) and folds back on hide (120 ms), starting from the payload's load so the previous payload never flashes; a show during a hide reverses from where it is, and a change of screen or position restarts from closed. `hide_now` is instant only without the frame. Placement, end kinds and the translucent window publish are shared with `Popup.qml` through `DrawerGeometry.js` (`place`, `window_rect`, `end_kinds`) and `DrawerWindowPublisher.qml`. In the goldeneye style it keeps its panel corner decor as a drawer, like a bar popup.

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
