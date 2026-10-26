local Bind = require("lib.key.bind") ---@class BindLib
local Menu = require("lib.actions.menu") ---@class Menu

-- Keys and labels for these come from the action manifest (home/oasis-djinn/.config/oasis-djinn/actions.json).
Bind.action("screenshot.take")
Bind.action("screenshot.pixel")
Bind.action("zoom.toggle")

-- Voice: while voxtype records, either key stops it and the recording's own mode handles the result.
-- Stop Voice ends everything instead: the session, a waiting picker and any recording, discarding what was said.
Bind.action("voice.dictate")
Bind.action("voice.command")
Bind.action("voice.stop")
Bind.action("voice.rapid")
Bind.action("voice.wake")

-- Not in the manifest yet: these pickers fall back to rofi when the bar lacks a provider, and the directory picker
-- follows `app.tui_file_manager`; an IPC-only binding would lose both. They move once the runner can fall back (2c).
Bind.leader_fn("CTRL + V", Menu.clipboard(), "Clipboard History")
Bind.leader_fn("CTRL + SHIFT + V", Menu.clipboard_delete(), "Delete Clipboard Entry")
Bind.leader_fn("CTRL + SPACE", Menu.zoxide(), "Jump to Directory")
Bind.leader_fn("CTRL + E", Menu.emoji(), "Emoji Picker")
Bind.action("picker.passwords")

Bind.action("overview.search")
Bind.action("overview.move")
Bind.action("overview.move_silent")

Bind.action("overview.open")
Bind.action("tmux.overview")

-- HyprVim Utilities
local function open_hyprvim_term() require("lua.plugins.hyprvim").command.prompt() end
local function jump_to_hyprvim_mark() require("lua.plugins.hyprvim").marks.enter_jump() end
Bind.leader_fn("SHIFT + SEMICOLON", open_hyprvim_term, "HyprVim Terminal")
Bind.leader_fn("APOSTROPHE", jump_to_hyprvim_mark, "Jump to Mark")
