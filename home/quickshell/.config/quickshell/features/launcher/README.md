# Launcher and pickers

The launcher is a fuzzy picker with one search box and list shared by every provider: apps, directories, emoji, clipboard, keybinds, running agent sessions and plain choices. Most are typed into and dock at the bottom of the focused monitor (or drop from the bar island you clicked). Agent sessions and the clipboard are mostly looked at, so they use a browse layout: they always drop from the center island at about the size of the Settings panel, never dock at the bottom.

## Browse pickers

Top to bottom: the search bar, a preview of the selected item, and a grid of cards. In NORMAL mode:

- `hjkl`, `0`/`$` and `gg`/`G` move through the grid; a click activates a card like Enter (the picker closes; a clipboard entry replaces the clipboard).
- `=` (or `+`) makes the preview bigger, `-` smaller, `p` hides it or restores its size. Sizes are off, small, medium, large and max; max hides the cards. Each open starts at large (agents) or medium (clipboard); the size is not remembered.
- `v` switches between the card grid and one-line rows (an agent row also shows its state badge). Every open starts on the grid.
- The first nine cards or rows fully on screen carry a corner number. A digit 1 to 9 selects that item and never opens it; Enter does. In INSERT the digits type into the search.
- Clipboard: `f` cycles the type filter all, text, images (shown in the search bar corner). Binary entries show only under all. Each open starts at all.
- When items continue past the visible area, the edge fades and a caret points on.

Both open in NORMAL by default; set each picker's start mode in Settings > Input > Typing, alone or by group.

An agent card shows the session's title, agent, state badge, short directory and last line of its tmux pane, refreshed every second; the preview shows the pane's bottom lines. The badge is working (outlined, primary), waiting (filled, warning), done (filled, green) or idle (outlined, dim). Under it a bar and tokens ("118k / 200k") show how full the context is: green below 50%, yellow from 50%, red from 80%; none when the session has no context data. A clipboard card shows an image thumbnail or the first three lines of text.

## Code

- `Picker.qml` is the search box and list; `Pickers.qml` registers the providers and `PickerIpc.qml` is the IPC handler. A provider subclasses `PickerProvider.qml` (see "Extending" in the [Quickshell README](../../README.md)).
- Providers: `AppsProvider`, `DirsProvider`, `EmojiProvider`, `ClipboardProvider`, `KeybindsProvider`, `ChoicesProvider`, `AgentsProvider`. Agent session parsing is `AgentSessions.js`; its card pieces are `AgentStateBadge.qml`, `AgentContextBar.qml` and `AnsiText.js`.
- `BrowseLayout.js` holds the preview-size and grid maths for the browse layout.
- `StartMode.js` and `TypingSettings.qml` hold the per-picker start mode and its Settings > Input > Typing rows.
- `HyprvimPrompt.qml` and `HyprvimPromptIpc.qml` are the `:` prompt; `hyprvim/` holds its pieces (`CompletionMenu.qml`, `OutputPane.qml`, `PromptSpec.js`, `VimMotions.js`).
- Tests are in `home/quickshell/tests/` (`picker_browse.js`, `agent_sessions.js`, `picker_start_mode.js`).
