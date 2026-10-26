local Bind = require("lib.key.bind") ---@class BindLib

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

Bind.action("clipboard.history")
Bind.action("clipboard.delete")

Bind.action("picker.dirs")
Bind.action("picker.emoji")
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
