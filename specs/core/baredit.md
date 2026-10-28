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
The owner edits the bar modules on the real bars instead of in a list: a full-screen mode over every monitor that has a bar, driven from the keyboard, where the bar being edited changes as keys are pressed. It opens with `qs ipc call bareditor open ""` (Settings > Bar modules > Edit bar opens it too).

## Requirements
- **BAREDIT-01** The editor opens over the real bars of every monitor with a bar and starts on the focused monitor's bar in NORMAL mode; monitors with no bar are skipped.
- **BAREDIT-02** Monitor select moves between monitors with h/j/k/l by screen position; Enter edits that bar; q closes.
- **BAREDIT-03** Esc in NORMAL goes up to monitor select; Esc at monitor select closes the editor, and q closes it from every state (cancelling a hidden module being carried).
- **BAREDIT-04** In NORMAL, h/l select the previous/next module (also j/k on a side bar), in the order the bar shows them.
- **BAREDIT-05** Shift+H/L move the selected module, crossing into the next side at the ends; on a sorted (lualine) bar a module never moves out of its section.
- **BAREDIT-06** Editing a monitor that shares the layout edits the shared layout, and every sharing monitor is highlighted.
- **BAREDIT-07** `o` gives a monitor its own copy of the layout; `o` again returns it to shared. The editor shows which mode is active.
- **BAREDIT-08** `c` in VISUAL toggles compact for the layout being edited: all sharing monitors on a shared layout, one monitor on its own. It leaves the per-module overrides (BAREDIT-25) alone.
- **BAREDIT-09** `x` moves the selected module to the hidden list and never deletes it.
- **BAREDIT-10** Retired, id not reused: `a` no longer adds a module with an argument and does nothing; the argument variants are in the HIDDEN list (BAREDIT-22).
- **BAREDIT-11** Changes apply to the real bars at once and are saved.
- **BAREDIT-12** `u` undoes and Ctrl+R redoes edits made in the session; a new edit clears redo.
- **BAREDIT-13** Tab shows the hidden modules and the argument variants (BAREDIT-22); Enter picks one up, h/l place it on the bar, Enter drops it, Esc cancels with nothing changed.
- **BAREDIT-14** Shift+V selects the whole bar; h/j/k/l move it to the left, bottom, top or right edge live; a sharing monitor changes the shared position, a monitor with its own layout only its own; Esc or Enter returns to NORMAL.
- **BAREDIT-15** Quickshell takes the keyboard and pointer (never a Hyprland submap); only one screen owns the keyboard and it follows the picked monitor; `?` shows a help box.
- **BAREDIT-16** [gap: untested] The look (highlight, mode indicator) is readable in every style; checked by screenshots only.
- **BAREDIT-17** Rapid edits never lose a change to the file reloading under them.
- **BAREDIT-18** A popup (Settings included) open when the editor opens is closed, and a popup opened under the editor closes the editor, so the keyboard is never contested.
- **BAREDIT-19** A monitor added or removed while the editor is open updates monitor select; losing the picked monitor returns to monitor select on another one, and losing the last bar closes the editor.
- **BAREDIT-20** In VISUAL, `x` forgets the saved bar position that h/j/k/l would write, with no prompt: a monitor with its own layout loses only its own saved position; a sharing monitor loses the shared position and any saved one of its own, which also moves own-layout monitors that follow the shared one. The bar then follows the shared position, bars.json or top. Nothing saved: nothing changes. `u` and Ctrl+R undo and redo in VISUAL too.
- **BAREDIT-21** [gap: untested] The VISUAL hint bar's mode block shows the bar's current edge under the mode name, updating after every move, forget, undo and redo, and offers `x forget` only when something is saved to forget; checked by screenshots only (the edge and forgettable state it reads are tested).
- **BAREDIT-22** HIDDEN lists, after the hidden modules, every argument variant of a module (system:memory, system:temperature) that is not on the layout being edited, so a picked variant is added on drop and leaves the list, and an own-layout monitor lacking one still sees it. Plain `system` and `system:cpu` are one module (both draw CPU only): Tab never offers system:cpu, offers system when neither is on the layout, and CPU cannot be added twice, and hiding or placing either spelling acts on both, whichever a sharing rule lists; a saved system:cpu entry keeps working. With nothing left to add the tray says "nothing to add".
- **BAREDIT-23** The hint bar lists every key the current mode acts on and no other (NORMAL includes Tab, Shift+V, u and Ctrl+R), from one table (`HintData.js`) that a test compares to the keys each mode accepts.
- **BAREDIT-24** The hint bar keeps its own size and sits on the screen edge the bar is not on, including after the bar moves to the other edge in VISUAL (it never stretches across the screen).
- **BAREDIT-25** `c` in NORMAL steps the selected module's own compact inherit -> on -> off -> inherit, keyed by the full entry (`system:cpu` and `system:memory` are independent; plain `system` and `system:cpu` are one module). The override is saved beside the layout's compact (the shared layout, or the monitor's own), wins over the layout's compact and over a bars.json rule's per-module one, and is undone and redone like any edit. The editor shows and steps from the override the module draws with, the rule's included, so every `c` changes what is drawn; a module the rule names has no inherit step, so `c` toggles it between on and off. Each monitor's marks come from its own rule. `o` copies the shared overrides into the own layout and returning to shared drops the own ones; hiding a module keeps its override, removing it drops it, and the `cava` to `media` rename carries it.
- **BAREDIT-26** `c` on a module with no compact form (the registry's `supports_compact`, set only where the drawing changes) changes nothing and the hint bar says so until the next key. The hint bar's `c` names what it acts on: the selected module's state (inherit, on, off, none) in NORMAL, the bar's compact in VISUAL.
- **BAREDIT-27** [gap: untested] A module with a compact override shows a small dot at its corner in NORMAL and HIDDEN, filled when forced on, a ring when forced off; checked by screenshots only (the list of marks it reads is tested).

## Look
The bar being edited gets a thin frame and a light tint in the theme's primary color. The selected module gets a line along the bar's inner edge, a caret pointing at it and its name on a plate past the caret, in the theme's secondary color; a monitor sharing the layout shows them fainter, without the frame. The mode (NORMAL, HIDDEN, VISUAL) sits in a hint bar at the screen edge the bar is not on, with whether the layout is shared by n monitors or own. VISUAL frames the whole bar, and its hint bar's mode block shows the bar's edge. HIDDEN lists the hidden modules and argument variants in a tray beside the hint bar. A module with its own compact override carries a small dot in the secondary color at its corner (filled on, ring off). Monitor select shows the screens as they sit, the picked one lit. The help box is the shared key help. The pointer keeps the system cursor: no picker skin, since the keyboard never moves it. Everything uses style tokens.

## Not covered
- Undo restores whole saved states, so it also reverts unrelated keys changed elsewhere during the session (the Directory switches, an edit made to the file by hand).
- The keyboard goes to the picked monitor's surface with an exclusive grab, because a handover to another screen otherwise waits for the pointer to move there. The pointer is swallowed on every screen, so nothing under the editor sees it.
- A module the bar hides while it has nothing to show can be selected; its mark sits at the nearest shown module.
- Keyboard only: dragging modules is not covered.
- The editor's windows are checked in the shadow session only, because no layer-shell window loads in the headless test.
