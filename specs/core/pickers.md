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
- **PICKERS-04** The preview has five sizes: off, small, medium, large and max. Whole rows of cards fill the room left under it, at least one below max, and an off preview leaves the whole area to the cards.
- **PICKERS-05** In NORMAL mode `=` (or `+`) makes the preview bigger, `-` smaller, and `p` hides it or brings it back at the size it had. The keys stop at max and at off, and a picker's own keys keep working.
- **PICKERS-06** [gap: untested] Each open starts the preview at the picker's default size: large for agent sessions, medium for the clipboard. Nothing is remembered between opens.
- **PICKERS-07** [gap: untested] In a browse picker `hjkl`, `0`/`$` and `gg`/`G` move through the cards' grid, and a click on a card picks it.
- **PICKERS-08** The agent preview shows the selected session's tmux pane with its whole width visible, as many of its bottom lines as fit, refreshed every second.
- **PICKERS-09** An agent card shows the session's title, agent, state (working, waiting, done or idle) and short directory, and the last line in its pane with words in it, refreshed every second while the picker is open. A waiting session's state stands out.
- **PICKERS-10** [gap: untested] A clipboard card shows an image entry's thumbnail, or the first three lines of a text entry; the preview shows the whole text, wrapped, or the image fitted.
- **PICKERS-11** The agent sessions and clipboard pickers open in NORMAL mode by default; each picker's start mode can be set in Settings > Input, alone or by its group.
- **PICKERS-12** When the cards or the list rows continue past the visible area, the hidden edge fades and a small caret beside it points on, as in Settings, and the selected item is scrolled clear of the fade. This holds for the single-row strip at large too.
- **PICKERS-13** In NORMAL mode `v` switches a browse picker between the card grid and a list of one-line rows (an icon, or a small thumbnail for a clipboard image, then label and description; an agent row also shows its state badge). Every open starts on the grid. The preview sizes work the same in both, and the rows fill the room left under the preview.
- **PICKERS-14** The first nine cards or rows wholly on screen carry a small corner number, in INSERT and NORMAL alike; a faded peek row does not count, and the numbers follow the view as it scrolls. In NORMAL a digit 1 to 9 selects that numbered item and never opens it; Enter does. In INSERT the digits type into the search.
- **PICKERS-15** In the clipboard picker `f` (NORMAL) cycles the type filter through all, text and images, shown in the search bar's corner beside the mode and the count. Binary entries show only under all. Every open starts at all.
- **PICKERS-16** `=` at large goes one step further to max, where the preview fills the body and the cards or rows are hidden, with no scroll cue or number hints; `-` steps back to large, and `p` hides max and brings it back like any other size.
- **PICKERS-17** An agent's state badge reads working (outlined, primary colour), waiting (filled, warning), done (filled, green) or idle (outlined, dim), so a finished session no longer looks idle.
- **PICKERS-18** An agent card and list row show how full the session's context is as tokens ("118k / 200k") and a thin bar, green below 50%, yellow from 50% and red from 80%. A session with no context data shows neither.

## Look
The browse layout follows the workspace overview's filmstrip view: the big preview above, the cards in a strip below, framed like the overview's workspace tiles with the selected card outlined in the caret color.

## Not covered
Persisting the preview size, and the browse layout for any picker other than agent sessions and clipboard.
