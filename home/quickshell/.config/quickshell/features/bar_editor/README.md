# Bar editor

Edit the bar modules on the bars themselves: a full-screen mode over every monitor that has a bar, driven from the keyboard, where the bar changes as you press keys. Open it from Settings > Bar modules > Edit bar (Settings closes and does not reopen), `hypr-act bareditor.open`, or `qs ipc call bareditor open ""` (an empty string is the focused monitor; `open DP-1` picks one; `toggle`, `close` and `state` exist too). `?` shows the key list. Changes apply and save at once. Keyboard only; dragging is not supported.

## Keys

`q` closes the editor from every mode (a module you are carrying is put back).

| Mode | Keys |
| --- | --- |
| Monitor select | `hjkl` pick a monitor by screen position, Enter edits its bar, `q` or Esc closes |
| NORMAL | `h`/`l` select the previous or next module (`j`/`k` too on a side bar), Shift+`H`/`L` move it (crossing to the next side at the ends; on a lualine bar a module stays in its section), `x` hide, `c` compact this module (inherit, on, off; a module a `bars.json` `compact_modules` rule names just toggles on and off), `o` own layout, `u` undo, Ctrl+R redo, Tab hidden, Shift+`V` whole bar, Esc back to monitor select |
| HIDDEN (Tab) | `h`/`l` select a hidden module, Enter picks it up, then `h`/`l` place it and Enter drops it; Esc cancels the carry. With nothing carried, Esc or Tab leaves |
| VISUAL (Shift+`V`) | `hjkl` move the whole bar to the left, bottom, top or right edge, `c` compact the whole bar, `x` forget the saved bar position (no prompt; offered only when one is saved), `u`/Ctrl+R undo and redo, Esc or Enter back |

## Shared or own layout

Monitors share one layout unless you press `o` on one, which gives it its own copy (`o` again returns it to shared). Editing a monitor that shares changes all of them, and all of them are highlighted. Moving the whole bar in VISUAL follows the same rule. Hiding never deletes a module: HIDDEN lists the hidden modules and the argument variants not on the layout (`system:memory`, `system:temperature`; plain `system` and `system:cpu` are one module, so only one is ever offered). A module with a compact override shows a dot at its corner, filled for on and a ring for off; `c` on a module with no compact form changes nothing and the hint bar says so.

Undo restores the whole saved bar state, so it also reverts other bar settings changed during the session.

## Code

- `BarEditor.qml` (singleton) holds the state (monitor, module, mode, undo stacks) and the key dispatcher `press("h")`. Every edit is a pure function in [`../bar/BarLayout.js`](../bar/README.md) applied through `BarSettings.set_state`; start there.
- `BarEditorWindow.qml` is one overlay per screen (`quickshell-bareditor`); only the picked monitor's window takes the keyboard. `../bar/BarItems.qml` is where `Bar.qml` publishes each live module so the overlay can mark it.
- `HintData.js` is the table of keys each mode lists on the hint bar (`HintBox.qml`, `HintContent.qml` draw it from the shared hint bar parts in `ui/keys/`, which the submap hint bar uses too); a test compares it to the keys each mode handles, so a new key goes in both.
- `HintDrawerWindow.qml` is the hint bar as a frame drawer, one window per screen, for a screen with the screen frame on (it grows from the edge the bar is not on, like the submap hint bar), on the shared `../bar/HintDrawer.qml`. In monitor select it carries `MonitorMap.qml` (the screens as they sit, the picked one lit, at most a third of the screen tall) above the hints and follows the picked screen: it folds and grows again when the pick or the mode crosses monitor select, since the drawer cannot resize while open. `BarEditorWindow` hides `HintBox` and its floating monitor box there and shows them on a screen without the frame.
- `BarEditorIpc.qml` is the `bareditor` IPC target.
- Tests: `lib/check.sh --only bar-editor` runs the real `BarSettings` and `BarEditor` headless (`home/quickshell/tests/bar_editor/`); pure edits are in `tests/bar_layout.js`. Layer-shell windows do not load headless, so check the windows with the `shadow` skill.
