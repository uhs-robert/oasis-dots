local Bind = require("lib.key.bind") ---@class BindLib
local Scripts = require("lib.scripts") ---@class Scripts
local Menu = require("lib.actions.menu") ---@class Menu

-- Screenshot
-- stylua: ignore start
local screenshot = function(action) return action and Scripts.screenshot .. " --" .. action or Scripts.screenshot end
Bind.cmd("Print",    screenshot(),         "Screenshot", { submap_universal = true })
Bind.leader_cmd("I", screenshot(),         "Screenshot")
Bind.leader_cmd("P", screenshot("pixel"),  "Color Picker")
Bind.leader_cmd("Z", Scripts.qs_ipc .. " call zoom toggle", "Zoom")

-- Speech to Text
Bind.cmd("CTRL + PERIOD",         Scripts.voxtype,        "Speech to Text")
Bind.cmd("CTRL + ALT + A",        Scripts.voxtype,        "Speech to Text")
Bind.cmd("CTRL + SHIFT + PERIOD", Scripts.voxcmd_listen,  "Voice Command")

-- Clipboard History
Bind.leader_fn("CTRL + V",         Menu.clipboard(),        "Clipboard History")
Bind.leader_fn("CTRL + SHIFT + V", Menu.clipboard_delete(), "Delete Clipboard Entry")

-- Pickers
Bind.leader_fn("CTRL + SPACE", Menu.zoxide(),    "Jump to Directory")
Bind.leader_fn("CTRL + E", Menu.emoji(),     "Emoji Picker")
Bind.leader_fn("CTRL + P", Menu.bitwarden(), "Passwords")

-- Window Search / Move
Bind.leader_fn("T",                 Menu.overview_search(),          "Search windows")
Bind.leader_fn("SHIFT + T",         Menu.overview_move(true),        "Move window in overview")
Bind.leader_fn("CTRL + SHIFT + T",  Menu.overview_move(false),       "Silent move window in overview")

-- Workspace Overview
Bind.fn("ALT + TAB",                Menu.overview(),                 "Workspace overview")
Bind.leader_fn("TAB",               Menu.overview(),                 "Workspace overview")
Bind.fn("ALT + GRAVE",              Menu.tmux_overview(),            "Tmux overview")

-- HyprVim Utilities
local function open_hyprvim_term() require("lua.plugins.hyprvim").command.prompt() end
local function jump_to_hyprvim_mark() require("lua.plugins.hyprvim").marks.enter_jump() end
Bind.leader_fn("SHIFT + SEMICOLON", open_hyprvim_term,    "HyprVim Terminal")
Bind.leader_fn("APOSTROPHE",        jump_to_hyprvim_mark, "Jump to Mark")
