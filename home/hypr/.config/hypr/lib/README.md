# Shared Lua libraries

The code that keymaps, extensions and `custom/` share. Come here to find a helper, or the place where an action or a desktop step is implemented.

## Code

- [`act/`](act/README.md): the action system.
- [`desktop/`](desktop/README.md): one file per desktop area.
- `key/`: bind and submap machinery (`bind.lua`, `submap.lua`, `submap_hint.lua`, `direction.lua`). The rules are in [keymaps](../keymaps/README.md).
- `closed_windows.lua`: remembers windows closed by keybinds so the last one can be reopened.
- `hypr.lua`: wrappers around the `hl` global for dispatch and eval.
- `json.lua`: JSON encode and decode.
- `missing_repos.lua`: collects missing repo-backed parts and posts one notification naming them.
- `scripts.lua`: the paths of the shell helpers in `scripts/` and `~/.local/bin`.
- `selection.lua`: the window selection that the Windows, Resize and Move submaps share.
- `state.lua`: the directory for this config's runtime state, honouring `XDG_STATE_HOME`.
- `utils.lua`: table merge and file write helpers.
- `workspaces.lua`: which monitor holds which slot under the current machine profile.
