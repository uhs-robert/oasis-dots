# Workspace overview

`overview/` holds the workspace overview (`Overview`, its frame, tiles, search list and aim overlays, `Voice.js` for the voice snapshot), the tmux overview (`TmuxOverview`, `TmuxTile`, `TmuxData.js`, `Ansi.js`), `WindowThumbnail` and the saved-session store (`Sessions`, `SessionJson.js`).

In the workspace overview, `[`/`]` cycle windows, `Tab`/`Shift + Tab` toggle the special workspaces, `s` picks a whole screen, `w` sends the selected workspace to a monitor (pick it like `s`, `Enter` confirms) and `W` swaps its windows with another workspace's (move to it, `Enter` confirms), and `f` toggles the view. Save mode (from Settings > Sessions) is the same overview with every window marked and no moving or closing. The share picker is the same overview with only shareable windows; there `r` opens the region selector, and Esc in it comes back.

## Workspace overview and voice

Voice drives the open overview through two things only: a snapshot file it publishes and one IPC entry, so voice and keys run the same functions. The voxcmd side is the Overview integration (`home/voxcmd/.config/voxcmd/README.md`).

- `$XDG_RUNTIME_DIR/voxcmd/overview.json`, rewritten (60 ms debounce) whenever the model, the marks or the mode change, and `{"version":1,"open":false}` while closed: `{version, open, special, marks: [address], monitors: [{id, slot, horizontal, vertical, focused}], items: [...]}`. A window item is `{n, kind: "window", id: address, label, workspace, monitor, marked}`, a workspace item `{n, kind: "workspace", id, label, workspace, monitor, marked: false, windows, shown}` (`id` and `workspace` are the id as a string, or `sp:<name>`). `n` for windows counts from 1 by monitor slot, workspace order and reading order; for workspaces it is the id (the position in hjkl order in the special view). `horizontal` (`left`, `middle`, `right`) and `vertical` (`top`, `middle`, `bottom`) come from the monitors' geometry (`features/overview/Voice.js`: rows by vertical position, then columns within a row) and are empty while there is one row or column to tell apart; `slot` is the `SUPER + CTRL + n` slot, 0 when unknown.
- `qs ipc call overview act <verb> "<args>"` returns `ok` or `error: <why>`. Window arguments are addresses; with none, `move`, `send` and `close` take the marks, or the selected window when nothing is marked, as `m` and `x` do. `mark`/`unmark <addr...>`, `clear`, `close [addr...]`, `focus <addr>` (closes the overview), `move <workspace> [addr...]`, `send <monitor> [addr...]` (to its visible workspace), `workspace <ref>` (focus, closes the overview), `workspace_to_monitor <id> <monitor>`, `swap_workspaces <ref> <ref>` (every window of one trades places with every window of the other) and `close_overview`.
- While voxcmd has a voice session of kind `overview` open (`VoxSessionState`), every window shows its `n` in a bordered badge at its bottom left, after a window glyph (nf-fa-window_maximize), and workspace chips read "WS n" (numeric names only). A marked window shows only its check badge at the top right while the numbers show, with no mark-order number.
- `w` and `W` call the same `move_workspace_to_monitor` and `swap_workspaces` the `act` verbs do.

## Tools

Everything here is optional; a missing tool only disables the feature next to it.

| Tool | Used for |
| --- | --- |
| `tmux` | The tmux overview and the tmux targets picker |
