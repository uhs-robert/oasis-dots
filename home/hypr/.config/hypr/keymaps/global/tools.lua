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

-- The pickers fall back to rofi when the bar lacks a provider; their performers are in lib/actions/performers.lua.
Bind.action("picker.clipboard")
Bind.action("picker.clipboard_delete")
Bind.action("picker.directory")
Bind.action("picker.emoji")
Bind.action("picker.passwords")

Bind.action("overview.search")
Bind.action("overview.move")
Bind.action("overview.move_silent")

Bind.action("overview.open")
Bind.action("tmux.overview")

-- HyprVim Utilities
Bind.action("hyprvim.terminal")
Bind.action("hyprvim.jump_mark")
