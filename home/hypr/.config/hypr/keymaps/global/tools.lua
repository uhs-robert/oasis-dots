local Bind = require("lib.key.bind") ---@class BindLib
local Scripts = require("lib.scripts") ---@class Scripts
local Menu = require("lib.actions.menu") ---@class Menu

-- Screenshot
-- stylua: ignore start
local screenshot = function(action) return action and Scripts.screenshot .. " --" .. action or Scripts.screenshot end
Bind.cmd("Print",    screenshot(),         "Print Options")
Bind.leader_cmd("P", screenshot("pixel"),  "Color Picker")

-- Speech to Text
Bind.cmd("CTRL + PERIOD",  Scripts.voxtype, "Speech to Text")
Bind.cmd("CTRL + ALT + A", Scripts.voxtype, "Speech to Text")

-- Clipboard History
Bind.leader_fn("CTRL + V",         Menu.clipboard(),        "Clipboard History")
Bind.leader_fn("CTRL + SHIFT + V", Menu.clipboard_delete(), "Delete Clipboard Entry")

-- Pickers
Bind.leader_fn("CTRL + SPACE", Menu.zoxide(),    "Jump to Directory")
Bind.leader_fn("CTRL + E", Menu.emoji(),     "Emoji Picker")
Bind.leader_fn("CTRL + P", Menu.bitwarden(), "Passwords")

-- Window Selector / Move
Bind.leader_fn("T",                 Menu.hyprwindow(),               "Find window")
Bind.leader_fn("SHIFT + T",         Menu.hyprwindow_move(true),      "Move to another window")
Bind.leader_fn("CTRL + SHIFT + T",  Menu.hyprwindow_move(false),     "Silent move to another window")

-- Workspace Overview
Bind.fn("ALT + TAB",                Menu.overview(),                 "Workspace overview")
Bind.leader_fn("SHIFT + TAB",       Menu.overview(),                 "Workspace overview")

-- HyprVim Utilities
local function open_hyprvim_term() require("lua.plugins.hyprvim").command.prompt() end
Bind.leader_fn("SHIFT + SEMICOLON", open_hyprvim_term, "HyprVim Terminal")
