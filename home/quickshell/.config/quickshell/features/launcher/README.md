# Launcher and pickers

The launcher is a fuzzy picker with one search box and list shared by every provider: apps, directories, emoji, clipboard, keybinds, running agent sessions, Firefox tabs, open windows and plain choices. Most are typed into and dock at the bottom of the focused monitor (or drop from the bar island you clicked). Agent sessions, Firefox tabs, windows and the clipboard are mostly looked at, so they use a browse layout: they always drop from the center island at about the size of the Settings panel, never dock at the bottom.

## Browse pickers

Top to bottom: the search bar, a preview of the selected item, and a grid of cards. In NORMAL mode:

- `hjkl`, `0`/`$` and `gg`/`G` move through the grid; a click activates a card like Enter (the picker closes; a clipboard entry replaces the clipboard).
- `=` (or `+`) makes the preview bigger, `-` smaller, `p` hides it or restores its size. Sizes are off, small, medium, large and max; max hides the cards. Each open starts at large (agents) or medium (clipboard, Firefox tabs, windows); the size is not remembered.
- Agents: Tab (or Shift+Tab) swaps the preview between the selected session's pane and Claude usage, the bars the keeptabs popup's Usage tab shows (under each weekly bar, where the week's pace so far leads: the time you'd hit the limit, in the warning colour, or the percent you'd end the week on; hidden for the first 12 hours after a reset); the cards stay and `hjkl` still moves. With the preview off, Tab brings it back at its last size on usage. Every open starts on the pane. In the clipboard, Firefox tabs and windows Tab does nothing; no browse picker steps rows with Tab.
- `v` switches between the card grid and one-line rows (an agent row also shows its state badge). Every open starts on the grid, except windows, which starts on the rows.
- The first nine cards or rows fully on screen carry a corner number. A digit 1 to 9 selects that item and never opens it; Enter does. In INSERT the digits type into the search.
- Clipboard: `f` cycles the type filter all, text, images (shown in the search bar corner). Binary entries show only under all. Each open starts at all.
- When items continue past the visible area, the edge fades and a caret points on.

All four open in NORMAL by default; set each picker's start mode in Settings > Input > Typing, alone or by group.

An agent card shows the session's title, agent, state badge, short directory and last line of its tmux pane (or, outside tmux, its kitty window), refreshed every second; the preview shows the pane's bottom lines, shrunk to fit the pane's width down to a readable size; a pane wider than that (on an ultrawide) wraps its long lines, and cuts its border lines at the edge. A kitty window needs `allow_remote_control` and `listen_on` in kitty.conf. The badge is working (outlined, primary), waiting (filled, warning), done (filled, green) or idle (outlined, dim). Under it a bar and tokens ("118k / 200k") show how full the context is: green below 50%, yellow from 50%, red from 80%; none when the session has no context data. A clipboard card shows an image thumbnail or the first three lines of text.

## Firefox tabs

Go > Shift+B (`picker.firefox_tabs`) lists every Firefox tab, most recently used first, with a picture of each. Enter switches to the tab and focuses its window. In NORMAL mode `x` closes the tab, `y` copies its address (the search bar corner says `URL COPIED`), and `f` cycles all windows, then each Firefox window in turn (`WINDOW 1/2` in the corner, where window 1 is the one used last). The search matches titles and addresses.

The list shows at once with the pictures saved last time. Fresh ones then swap in a few tabs at a time, the selected tab first. An unloaded tab keeps its last picture, dimmed, and says `unloaded`. A tab never captured shows its icon and title. Only icons Firefox hands over inline are drawn, so the bar fetches nothing from the web. Other tabs get a globe.

It needs voxcmd's Firefox extension: stow `voxcmd`, run `just firefox-extension` and restart Firefox (details in [its README](../../../../../../extras/voxcmd-firefox/README.md)). Without it the picker shows that hint instead of a list. Private windows never show, since the extension cannot see them.

## Windows

Leader+T, Applications > Space and Go > W (`picker.windows`) list every open window, most recently focused first, special workspaces included. Each row shows the app icon, title, class and workspace, and the preview above shows the selected window live (one still frame on battery). It opens on the rows with the window before the focused one selected, so Enter right away goes back to the last window. Enter focuses the selected window. In NORMAL mode `x` closes it and `f` cycles all windows, this monitor's, then this workspace's (`MONITOR` or `WORKSPACE` in the search bar corner). The search matches class, initial class, workspace and title, as the workspace overview's `/` search does. Without the bar the binds open rofi's window list.

## Voice answers

The voice key answers an open choices picker however it opened: a number, a choice's name, "expand two" or "cancel". The keys work as before. Each row shows its number in dim text so you know what to say. A label that already starts with its own position, such as "1. " on the first row, gets no second number. Numbers follow the item, so a search does not renumber, and an expansion list restarts at 1. While the screen is locked, a voice answer is refused. `PickerVoice` publishes the open picker for voxcmd and takes the answers back through `picker answer`, `expand` and `cancel`. The file and the calls are in the voxcmd README under [Pickers the bar publishes](../../../../../voxcmd/.config/voxcmd/README.md#pickers-the-bar-publishes). Only the choices picker opts in (`PickerProvider.voice_answerable`). The fuzzy pickers and the rofi fallback stay keyboard only.

## Code

- `Picker.qml` is the search box and list; `Pickers.qml` registers the providers and `PickerIpc.qml` is the IPC handler. `PickerVoice.qml` publishes the open voice-answerable picker for voxcmd and checks each voice answer's token. A provider subclasses `PickerProvider.qml` (see "Extending" in the [Quickshell README](../../README.md)).
- Providers: `AppsProvider`, `DirsProvider`, `EmojiProvider`, `ClipboardProvider`, `KeybindsProvider`, `ChoicesProvider`, `AgentsProvider`, `FirefoxTabsProvider`, `WindowsProvider`. Agent session parsing is `AgentSessions.js`; its card pieces are `AgentStateBadge.qml`, `AgentContextBar.qml` and `AnsiText.js`.
- `FirefoxTabsProvider.qml` talks to the extension through `firefox-tab request` (voxcmd's socket client, in `home/voxcmd/.local/share/voxcmd/`); `FirefoxTabs.js` reads its replies, orders the tabs and cycles the window filter; `TabThumbnail.qml` and `TabFavicon.qml` draw a tab's picture and icon.
- `WindowsProvider.qml` builds its rows from `WindowState.entries()` (`core/WindowEntries.js`, shared with the overview's search, also holds the `f` filter) and draws pictures with `ui/WindowThumbnail.qml`.
- `BrowseLayout.js` holds the preview-size and grid maths for the browse layout.
- `ClipboardFilter.js` holds the clipboard picker's type filter (`f`).
- `StartMode.js` and `TypingSettings.qml` hold the per-picker start mode and its Settings > Input > Typing rows.
- `HyprvimPrompt.qml` and `HyprvimPromptIpc.qml` are the `:` prompt; `hyprvim/` holds its pieces (`CompletionMenu.qml`, `OutputPane.qml`, `PromptSpec.js`, `VimMotions.js`).
- Tests are in `home/quickshell/tests/` (`picker_browse.js`, `clipboard_filter.js`, `agent_sessions.js`, `picker_start_mode.js`, `firefox_tabs.js`, `window_entries.js`).
