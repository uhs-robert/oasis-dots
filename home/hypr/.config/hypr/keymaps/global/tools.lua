local Bind = require("lib.key.bind") ---@class BindLib
local Scripts = require("lib.scripts") ---@class Scripts
local Config = require("config") ---@class Config

local MENU = Config.app.menu

-- Screenshot
-- stylua: ignore start
local screenshot = function(action) return action and Scripts.screenshot .. " --" .. action or Scripts.screenshot end
Bind.cmd("Print",    screenshot(),         "Print Options")
Bind.leader_cmd("P", screenshot("pixel"),  "Color Picker")

-- Speech to Text
Bind.cmd("CTRL + PERIOD",  Scripts.voxtype, "Speech to Text")
Bind.cmd("CTRL + ALT + A", Scripts.voxtype, "Speech to Text")

-- Clipboard History Lookup
local cmd_search_clipboard = "cliphist list | "
  .. MENU
  .. " -i -dmenu -p 'Search clipboard history...' | cliphist decode | wl-copy"
Bind.leader_cmd("CTRL + V", cmd_search_clipboard, "Clipboard History")

-- Window Selector / Move
local function select_window(action) return Scripts.window_selector .. " --" .. action end
Bind.leader_cmd("T",                MENU .. " -i -show hyprwindow",  "Find window")
Bind.leader_cmd("SHIFT + T",        select_window("move"),           "Move to another window")
Bind.leader_cmd("CTRL + SHIFT + T", select_window("move-silent"),    "Silent move to another window")
