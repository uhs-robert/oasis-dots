local Bind = require("lib.key.bind") ---@class BindLib
local Menu = require("lib.actions.menu") ---@class Menu

-- The 14 actions (zoom, screenshot, voice, passwords, overviews) bind their own keys when this file loads.
require("lib.actions.defs.tools")

-- Not defined as actions yet: these pickers fall back to rofi when the bar lacks a provider, and the directory picker
-- follows `app.tui_file_manager`; an IPC-only action would lose both. They move once an action can fall back (2c).
Bind.leader_fn("CTRL + V", Menu.clipboard(), "Clipboard History")
Bind.leader_fn("CTRL + SHIFT + V", Menu.clipboard_delete(), "Delete Clipboard Entry")
Bind.leader_fn("CTRL + SPACE", Menu.zoxide(), "Jump to Directory")
Bind.leader_fn("CTRL + E", Menu.emoji(), "Emoji Picker")

-- HyprVim Utilities
local function open_hyprvim_term() require("lua.plugins.hyprvim").command.prompt() end
local function jump_to_hyprvim_mark() require("lua.plugins.hyprvim").marks.enter_jump() end
Bind.leader_fn("SHIFT + SEMICOLON", open_hyprvim_term, "HyprVim Terminal")
Bind.leader_fn("APOSTROPHE", jump_to_hyprvim_mark, "Jump to Mark")
