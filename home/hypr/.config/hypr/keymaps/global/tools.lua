local Bind = require("lib.key.bind")
local Scripts = require("lib.scripts")
local Config = require("config")

local MENU = Config.app.menu

-- stylua: ignore start
Bind.cmd("Print",          Scripts.screenshot,                { desc = "Print Options" })
Bind.leader_cmd("P",       Scripts.screenshot .. " --pixel",  { desc = "Color Picker" })

Bind.cmd("CTRL + PERIOD",  Scripts.voxtype, { desc = "Speech to Text" })
Bind.cmd("CTRL + ALT + A", Scripts.voxtype, { desc = "Speech to Text" })

local cmd_search_clipboard = "cliphist list | "
  .. MENU
  .. " -i -dmenu -p 'Search clipboard history...' | cliphist decode | wl-copy"
Bind.leader_cmd("CTRL + V", cmd_search_clipboard, { desc = "Clipboard History" })

Bind.leader_cmd("T",             MENU .. " -i -show hyprwindow",              { desc = "Find window" })
Bind.leader_cmd("SHIFT + T",     Scripts.window_selector .. " --move",        { desc = "Move to window" })
Bind.leader_cmd("CTRL + SHIFT + T", Scripts.window_selector .. " --move-silent", { desc = "Silent move to window" })
