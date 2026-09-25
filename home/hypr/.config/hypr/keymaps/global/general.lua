local Bind = require("lib.key.bind") ---@class BindLib
local Config = require("config") ---@class Config
local Direction = require("lib.key.direction") ---@class Direction
local Window = require("lib.actions.window") ---@class WindowActions

-- stylua: ignore start
local OPTS = {
  universal = function(description) return { submap_universal = true, desc = description } end,
}

-- Utility
Bind.leader_cmd("SLASH",  require("lib.scripts").keybind_help, OPTS.universal("Keybind Help"))

-- Window Actions
Bind.leader_key("X",   Window.close(),             "Close Window")
Bind.leader_key("F",   Window.fullscreen_toggle(), "Toggle Fullscreen")
Bind.leader_key("TAB", Window.focus_last(),        "Previous Window")

-- Window Focus/Movement
local shift_leader = Bind.leader ~= "" and (Bind.leader .. " + SHIFT") or "SHIFT"
local focus_actions = { left = Window.focus_dir("l"), down = Window.focus_dir("d"), up = Window.focus_dir("u"), right = Window.focus_dir("r") }
local move_actions  = { left = Window.move_dir("l"),  down = Window.move_dir("d"),  up = Window.move_dir("u"),  right = Window.move_dir("r") }
Bind.keys(Direction.binds(focus_actions, "Focus",       Bind.leader,  { submap_universal = true }))
Bind.keys(Direction.binds(move_actions,  "Move Window", shift_leader, { submap_universal = true }))

-- Float Cycle (notification toasts first)
Bind.leader_key("BRACKETLEFT",  Window.focus_toast_or_float("prev"), "Prev Toast/Float")
Bind.leader_key("BRACKETRIGHT", Window.focus_toast_or_float("next"), "Next Toast/Float")

-- Window Special
Bind.leader_key("S",         Window.toggle_special("scratchpad"),  OPTS.universal("Toggle Scratchpad"))
Bind.leader_key("SHIFT + S", Window.move_to_special("scratchpad"), OPTS.universal("Move to Scratchpad"))

-- Monitor Focus/Movement
for i = 1, #Config.monitors > 0 and math.min(#Config.monitors, 10) or 10 do
  local key = i % 10
  Bind.leader_key("CTRL + " .. key,         Window.focus_monitor(i),   { desc = "Focus Monitor " .. i })
  Bind.leader_key("CTRL + SHIFT + " .. key, Window.move_to_monitor(i), { desc = "Move to Monitor " .. i })
end
