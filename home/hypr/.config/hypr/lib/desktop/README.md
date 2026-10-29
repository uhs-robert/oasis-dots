# Desktop areas

What the desktop does, one file per area. An action's `run` hands its work to these files (see [actions](../act/README.md)). Come here to change how a window, workspace, app or media step behaves.

These files know nothing about action ids. Keymaps, extensions and `custom/` call them directly too.

## Code

- `apps.lua`: run an app, or focus its window when one is open.
- `cursor.lua`: pointer movement, scrolling, clicking and key dispatch.
- `delete.lua`: close every window on the workspace, or every window of one kind of app.
- `media.lua`: volume, brightness and player control.
- `menu.lua`: open the bar's picker or the configured menu app.
- `move.lua`: nudge windows, for the Move submap.
- `resize.lua`: resize windows, for the Resize submap.
- `terminal.lua`: the configured terminal, a command in it, or the bottom-half terminal.
- `window.lua`: focus direction, move direction, close, fullscreen, scratchpad and monitors.
- `workspace.lua`: focus, move a window, cycle and scroll workspaces.
