---
id: pickers
title: Pickers
status: draft
prs: []
implements:
  - home/quickshell/.config/quickshell/features/launcher
depends_on: [keys]
---
# Pickers

## What it is for
The owner picks things from the keyboard: an app, a directory, an emoji, a clipboard entry, a running agent session. Every picker shares one search box and list. Most are typed into and dock at the bottom of the screen; the agent sessions and clipboard pickers are mostly looked at, so they use a browse layout with a large preview and cards.

## Requirements
- **PICKERS-01** [gap: untested] A list picker opened from a keybind or IPC docks at the bottom of the focused monitor; opened from a bar island it drops from that island.
- **PICKERS-02** [gap: untested] The agent sessions and clipboard pickers always drop from the center island of the focused monitor, at about the size of the Settings panel, including when opened from a keybind or IPC. They never dock at the bottom.
- **PICKERS-03** [gap: untested] A browse picker shows, top to bottom, the search bar, a preview of the selected item, and a grid of fixed-size cards with as many columns as the width allows.
- **PICKERS-04** The preview has four sizes: off, small, medium and large. Whole rows of cards fill the room left under it, at least one, and an off preview leaves the whole area to the cards.
- **PICKERS-05** In NORMAL mode `=` (or `+`) makes the preview bigger, `-` smaller, and `p` hides it or brings it back at the size it had. The keys stop at the largest and at off, and a picker's own keys keep working.
- **PICKERS-06** [gap: untested] Each open starts the preview at the picker's default size: large for agent sessions, medium for the clipboard. Nothing is remembered between opens.
- **PICKERS-07** [gap: untested] In a browse picker `hjkl`, `0`/`$` and `gg`/`G` move through the cards' grid, and a click on a card picks it.
- **PICKERS-08** The agent preview shows the selected session's tmux pane with its whole width visible, as many of its bottom lines as fit, refreshed every second.
- **PICKERS-09** An agent card shows the session's title, agent, state (working, waiting or idle) and short directory, and the last line in its pane with words in it, refreshed every second while the picker is open. A waiting session's state stands out.
- **PICKERS-10** [gap: untested] A clipboard card shows an image entry's thumbnail, or the first three lines of a text entry; the preview shows the whole text, wrapped, or the image fitted.
- **PICKERS-11** The agent sessions and clipboard pickers open in NORMAL mode by default; each picker's start mode can be set in Settings > Input, alone or by its group.

## Look
The browse layout follows the workspace overview's filmstrip view: the big preview above, the cards in a strip below, framed like the overview's workspace tiles with the selected card outlined in the caret color.

## Not covered
Persisting the preview size, and the browse layout for any picker other than agent sessions and clipboard.
