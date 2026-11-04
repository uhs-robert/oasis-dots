# Launcher and pickers

The launcher is a fuzzy picker with one search box and list shared by every provider: apps, directories, tmuxifier projects, emoji, clipboard, keybinds, running agent sessions, Firefox tabs, tmux windows, open windows and plain choices. Most are typed into and dock at the bottom of the focused monitor (or drop from the bar island you clicked). Agent sessions, Firefox tabs, tmux windows, windows and the clipboard are mostly looked at, so they use a browse layout: they always drop from the center island at about the size of the Settings panel, never dock at the bottom.

## Projects

Go > P (`menu.tmux`) lists your tmuxifier layouts (the `*.session.sh` files in `$TMUXIFIER_LAYOUT_PATH`, else `~/.tmuxifier/layouts`) by name, with dashes and underscores shown as spaces. A dot marks a layout whose tmux session already runs: the session the layout names with `session_name`, else one named like the file. Enter focuses the terminal showing that session. A running session with no terminal gets a new one attached to it, and any other layout loads in a new terminal. The search also matches the file and session names. Without the bar Go > P opens the same list in rofi.

## Browse pickers

Top to bottom: the search bar, a preview of the selected item, and a grid of cards. In NORMAL mode:

- `hjkl`, `0`/`$` and `gg`/`G` move through the grid; a click activates a card like Enter (the picker closes; a clipboard entry replaces the clipboard).
- `=` (or `+`) makes the preview bigger, `-` smaller, `p` hides it or restores its size. Sizes are off, small, medium, large and max; max hides the cards. Each open starts at large (agents) or medium (clipboard, Firefox tabs, tmux windows, windows); the size is not remembered.
- Agents: Tab (or Shift+Tab) swaps the preview between the selected session's pane and Claude usage, the bars the keeptabs popup's Usage tab shows (under each weekly bar, where the week's pace so far leads: the time you'd hit the limit, in the warning colour, or the percent you'd end the week on; hidden for the first 12 hours after a reset); the cards stay and `hjkl` still moves. With the preview off, Tab brings it back at its last size on usage. Every open starts on the pane. In the clipboard, Firefox tabs, tmux windows and windows Tab does nothing; no browse picker steps rows with Tab.
- `v` switches between the card grid and one-line rows (an agent row also shows its state badge). Agents and the clipboard open on the grid, Firefox tabs, tmux windows and windows on the rows. The view is not remembered.
- The first nine cards or rows fully on screen carry a corner number. A digit 1 to 9 selects that item and never opens it; Enter does. In INSERT the digits type into the search.
- Clipboard: `f` cycles the type filter all, text, images (shown in the search bar corner). Binary entries show only under all. Each open starts at all.
- When items continue past the visible area, the edge fades and a caret points on.

All five open in NORMAL by default; set each picker's start mode in Settings > Input > Typing, alone or by group.

An agent card shows the session's title, agent, state badge, short directory and last line of its tmux pane (or, outside tmux, its kitty window), refreshed every second; the preview shows the pane's bottom lines, shrunk to fit the pane's width down to a readable size; a pane wider than that (on an ultrawide) wraps its long lines, and cuts its border lines at the edge. A kitty window needs `allow_remote_control` and `listen_on` in kitty.conf. The badge is working (outlined, primary), waiting (filled, warning), done (filled, green) or idle (outlined, dim). Under it a bar and tokens ("118k / 200k") show how full the context is: green below 50%, yellow from 50%, red from 80%; none when the session has no context data. A clipboard card shows an image thumbnail or the first three lines of text.

## Firefox tabs

Leader+Shift+T or Leader > T (`picker.firefox_tabs`) lists every Firefox tab with a picture of each, as one-line rows (`v` for the grid). Enter switches to the tab and focuses its window. In NORMAL mode:

- `s` switches the sort. Tab order, the default, groups the tabs by window, each window in its tab-bar order under a header such as `WINDOW 1 · 14 TABS · <title of its active tab>`. Recent is one list, most recently used first, with a `W1` or `W2` badge on each tab for its window. The search bar corner shows the sort (`TAB ORDER` or `RECENT`), and the picker keeps the last one across opens and bar restarts.
- `f` cycles all windows, then each Firefox window in turn (`WINDOW 1/3` in the corner).
- `x` closes the tab, and `y` copies its address (the corner says `URL COPIED`).

Windows are numbered in the order Firefox opened them, the same in the headers, the badges and the filter. The search matches titles and addresses. In tab order it keeps the groups: a window's header shows only while one of its tabs matches, and counts the matching tabs. Headers are never selected: `hjkl`, `gg`/`G` and the digits skip them.

The list shows at once with the pictures saved last time. Fresh ones then swap in a few tabs at a time, the selected tab first. An unloaded tab keeps its last picture, dimmed, and says `unloaded`. A tab never captured shows its icon and title. Only icons Firefox hands over inline are drawn, so the bar fetches nothing from the web. Other tabs get a globe.

It needs voxcmd's Firefox extension: stow `voxcmd`, run `just firefox-extension` and restart Firefox (details in [its README](../../../../../../extras/voxcmd-firefox/README.md)). Without it the picker shows that hint instead of a list. Private windows never show, since the extension cannot see them.

## Tmux windows

Alt+Grave, Leader > Ctrl+T and tmux's `prefix w` (`picker.tmux`) list every tmux window, as one-line rows (`v` for the grid). Each row shows the window's index and name and its active pane's command and short path. A card adds its session, pane count and the pane's last lines. The preview shows the chosen pane live (one capture per selection on battery), shrunk to fit as the agents preview is. It opens on the window the most recently used tmux client shows. While it is open, the list reloads every second (every 3 seconds on battery). A new window joins the end of its session, or of the recent list. A closed one drops out. The other rows keep their places until the next open, `s` or `x`. In NORMAL mode:

- Enter goes to the window and pane. When a terminal already shows the session, tmux selects them there and that terminal is focused. Otherwise the most recent client switches to the session, or a new terminal attaches to it.
- `[` and `]` choose the previous or next pane of the window, top to bottom, then left to right. The preview corner says which (`PANE 2/3 · nvim`). Every open starts on each window's active pane.
- `s` switches the sort. Session order, the default, puts each session's windows by index under a header such as `SESSION 1 · work · 3 WINDOWS · ATTACHED`. Recent is one list, most recently active window first, with the session's name on each row. The search bar corner shows the sort (`SESSIONS` or `RECENT`), and the picker keeps the last one across opens and bar restarts.
- `f` cycles all sessions, then each session in turn (`SESSION 1/3` in the corner).
- `x` kills the window. The picker stays open and lists the windows again.

The search matches window names, session names, pane commands and short paths. Headers are never selected. Without tmux, or with no tmux server running, the picker says so instead of a list. Without the bar the binds show a notice, and `prefix w` opens tmux's own tree chooser.

## Windows

Leader+T, Applications > Space and Go > W (`picker.windows`) list every open window, most recently focused first, special workspaces included. Each row shows the app icon, title, class and workspace, and the preview above shows the selected window live (one still frame on battery). It opens on the rows with the window before the focused one selected, so Enter right away goes back to the last window. Enter focuses the selected window. In NORMAL mode `x` closes it and `f` cycles all windows, this monitor's, then this workspace's (`MONITOR` or `WORKSPACE` in the search bar corner). The search matches class, initial class, workspace and title, as the workspace overview's `/` search does. Without the bar the binds open rofi's window list.

## Voice answers

The voice key answers an open choices picker however it opened: a number, a choice's name, "expand two" or "cancel". The keys work as before. Each row shows its number in dim text so you know what to say. A label that already starts with its own position, such as "1. " on the first row, gets no second number. Numbers follow the item, so a search does not renumber, and an expansion list restarts at 1. While the screen is locked, a voice answer is refused. `PickerVoice` publishes the open picker for voxcmd and takes the answers back through `picker answer`, `expand` and `cancel`. The file and the calls are in the voxcmd README under [Pickers the bar publishes](../../../../../voxcmd/.config/voxcmd/README.md#pickers-the-bar-publishes). Only the choices picker opts in (`PickerProvider.voice_answerable`). The fuzzy pickers and the rofi fallback stay keyboard only.

## Code

- `Picker.qml` is the search box and list; `Pickers.qml` registers the providers and `PickerIpc.qml` is the IPC handler. `PickerVoice.qml` publishes the open voice-answerable picker for voxcmd and checks each voice answer's token. A provider subclasses `PickerProvider.qml` (see "Extending" in the [Quickshell README](../../README.md)).
- Providers: `AppsProvider`, `DirsProvider`, `EmojiProvider`, `ClipboardProvider`, `KeybindsProvider`, `ChoicesProvider`, `AgentsProvider`, `FirefoxTabsProvider`, `TmuxProvider`, `WindowsProvider`, `ProjectsProvider`. Agent session parsing is `AgentSessions.js`; its card pieces are `AgentStateBadge.qml`, `AgentContextBar.qml` and `AnsiText.js`. `AnsiPane.qml` draws a captured terminal pane shrunk to fit, in the agents and tmux previews.
- `FirefoxTabsProvider.qml` talks to the extension through `firefox-tab request` (voxcmd's socket client, in `home/voxcmd/.local/share/voxcmd/`). `FirefoxTabs.js` reads its replies, sorts and numbers the tabs, titles the window headers and cycles the window filter. `FirefoxTabsSettings.qml` keeps the last sort in `firefox_tabs.json` under the Quickshell state dir. `TabThumbnail.qml` and `TabFavicon.qml` draw a tab's picture and icon.
- `TmuxProvider.qml` lists, captures, kills and selects tmux windows. `TmuxWindows.js` builds the tmux commands, reads their output into one item per window, titles the session headers, sorts, filters and cycles panes, and finds the terminal that shows a session. `TmuxSettings.qml` keeps the last sort in `tmux.json` under the Quickshell state dir.
- `WindowsProvider.qml` builds its rows from `WindowState.entries()` (`core/WindowEntries.js`, shared with the overview's search, also holds the `f` filter) and draws pictures with `ui/WindowThumbnail.qml`.
- `BrowseLayout.js` holds the preview-size and grid maths for the browse layout. It also lays out the browse view's lines: the headers of a grouped provider (`PickerProvider.grouped`), then the cards or rows.
- `Picker.qml` draws each browse card or list row's frame. `EntryBody.qml` loads the provider's `card` or `row` inside it, or `GenericCard.qml` or `GenericRow.qml` for a provider without one, and `QuickHint.qml` is its 1-9 digit. `EntryIcon.qml` is an item's icon or glyph, in the docked list and the generic card and row.
- `ProjectsProvider.qml` lists the tmuxifier layouts and hands the chosen one to `hypr/scripts/tmux-layout`, which also holds the rofi fallback. `Projects.js` holds its listing script, the names and the running-session match.
- `ClipboardFilter.js` holds the clipboard picker's type filter (`f`).
- `StartMode.js` and `TypingSettings.qml` hold the per-picker start mode and its Settings > Input > Typing rows.
- `HyprvimPrompt.qml` and `HyprvimPromptIpc.qml` are the `:` prompt; `hyprvim/` holds its pieces (`CompletionMenu.qml`, `OutputPane.qml`, `PromptSpec.js`, `VimMotions.js`).
- Tests are in `home/quickshell/tests/` (`picker_browse.js`, `clipboard_filter.js`, `agent_sessions.js`, `picker_start_mode.js`, `firefox_tabs.js`, `tmux_windows.js`, `window_entries.js`, `projects.js`).
