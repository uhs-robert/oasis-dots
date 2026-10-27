---
id: baredit
title: Bar editor
status: draft
prs: []
implements:
  - home/quickshell/.config/quickshell/features/bar_editor
  - home/quickshell/.config/quickshell/features/bar/BarLayout.js
depends_on: []
actions: []
keys: []
---
# Bar editor

## What it is for
The owner edits the bar modules on the real bars instead of in a list: a full-screen mode over every monitor that has a bar, driven from the keyboard, where the bar being edited changes as keys are pressed. It opens with `qs ipc call bareditor open ""` (the Settings row that opens it comes later).

## Requirements
- **BAREDIT-01** The editor opens over the real bars of every monitor with a bar and starts on the focused monitor's bar in NORMAL mode; monitors with no bar are skipped.
- **BAREDIT-02** Monitor select moves between monitors with h/j/k/l by screen position; Enter edits that bar; q closes.
- **BAREDIT-03** Esc in NORMAL goes up to monitor select; Esc at monitor select closes the editor, and q closes it from every state (cancelling a hidden module being carried), except in the `a` prompt, where q is a typed letter and Esc cancels the prompt.
- **BAREDIT-04** In NORMAL, h/l select the previous/next module (also j/k on a side bar), in the order the bar shows them.
- **BAREDIT-05** Shift+H/L move the selected module, crossing into the next side at the ends; on a sorted (lualine) bar a module never moves out of its section.
- **BAREDIT-06** Editing a monitor that shares the layout edits the shared layout, and every sharing monitor is highlighted.
- **BAREDIT-07** `o` gives a monitor its own copy of the layout; `o` again returns it to shared. The editor shows which mode is active.
- **BAREDIT-08** `c` toggles compact for the layout being edited: all sharing monitors on a shared layout, one monitor on its own.
- **BAREDIT-09** `x` moves the selected module to the hidden list and never deletes it.
- **BAREDIT-10** `a` adds a module with an argument (for example system:cpu).
- **BAREDIT-11** Changes apply to the real bars at once and are saved.
- **BAREDIT-12** `u` undoes and Ctrl+R redoes edits made in the session; a new edit clears redo.
- **BAREDIT-13** Tab shows hidden modules; Enter picks one up, h/l place it on the bar, Enter drops it, Esc cancels with nothing changed.
- **BAREDIT-14** Shift+V selects the whole bar; h/j/k/l move it to the left, bottom, top or right edge live; a sharing monitor changes the shared position, a monitor with its own layout only its own; Esc or Enter returns to NORMAL.
- **BAREDIT-15** Quickshell takes the keyboard and pointer (never a Hyprland submap); only one screen owns the keyboard and it follows the picked monitor; `?` shows a help box.
- **BAREDIT-16** [gap: untested] The look (highlight, mode indicator) is readable in every style; checked by screenshots only.
- **BAREDIT-17** Rapid edits never lose a change to the file reloading under them.
- **BAREDIT-18** A popup (Settings included) open when the editor opens is closed, and a popup opened under the editor closes the editor, so the keyboard is never contested.
- **BAREDIT-19** A monitor added or removed while the editor is open updates monitor select; losing the picked monitor returns to monitor select on another one, and losing the last bar closes the editor.

## Look
The selected module gets a line along the bar's inner edge and a caret pointing at it, in the style's accent; a monitor sharing the layout shows it fainter. The mode (`-- NORMAL --`, `-- HIDDEN --`, `-- VISUAL --`) sits in a hint bar at the screen edge the bar is not on, with whether the layout is shared by n monitors or own. VISUAL frames the whole bar. HIDDEN lists the hidden modules in a tray above the hint bar. Monitor select shows the screens as they sit, the picked one lit. The help box is the shared key help. The pointer is the style's picker cursor (blank system cursor under a skin). Everything uses style tokens.

## Not covered
- Undo restores whole saved states, so it also reverts unrelated keys changed elsewhere during the session (the Directory switches, an edit made to the file by hand).
- The keyboard goes to the picked monitor's surface with an exclusive grab, because a handover to another screen otherwise waits for the pointer to move there. The pointer is swallowed on every screen, so nothing under the editor sees it.
- A module the bar hides while it has nothing to show can be selected; its mark sits at the nearest shown module, and the hint bar names the selected module.
- Keyboard only: dragging modules is not covered.
- The editor's windows are checked in the shadow session only, because no layer-shell window loads in the headless test.
