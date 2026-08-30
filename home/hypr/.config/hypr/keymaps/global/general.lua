local Bind = require("lib.key.bind") ---@class BindLib
local Config = require("config") ---@class Config
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
Bind.leader_key({ "H", "LEFT" },  Window.focus_dir("l"), OPTS.universal("Focus Left"))
Bind.leader_key({ "J", "DOWN" },  Window.focus_dir("d"), OPTS.universal("Focus Down"))
Bind.leader_key({ "K", "UP" },    Window.focus_dir("u"), OPTS.universal("Focus Up"))
Bind.leader_key({ "L", "RIGHT" }, Window.focus_dir("r"), OPTS.universal("Focus Right"))

Bind.leader_key({ "SHIFT + H", "SHIFT + LEFT" },  Window.move_dir("l"), OPTS.universal("Move Window Left"))
Bind.leader_key({ "SHIFT + J", "SHIFT + DOWN" },  Window.move_dir("d"), OPTS.universal("Move Window Down"))
Bind.leader_key({ "SHIFT + K", "SHIFT + UP" },    Window.move_dir("u"), OPTS.universal("Move Window Up"))
Bind.leader_key({ "SHIFT + L", "SHIFT + RIGHT" }, Window.move_dir("r"), OPTS.universal("Move Window Right"))

-- Float Cycle
Bind.leader_key("BRACKETLEFT",  Window.cycle_float("prev"), "Prev Float")
Bind.leader_key("BRACKETRIGHT", Window.cycle_float("next"), "Next Float")

-- Window Special
Bind.leader_key("S",         Window.toggle_special("scratchpad"),  OPTS.universal("Toggle Scratchpad"))
Bind.leader_key("SHIFT + S", Window.move_to_special("scratchpad"), OPTS.universal("Move to Scratchpad"))

-- Monitor Focus/Movement
for i = 1, math.max(#Config.monitors, 10) do
  local key = i % 10
  Bind.leader_key("CTRL + " .. key,         Window.focus_monitor(i),   { desc = "Focus Monitor " .. i })
  Bind.leader_key("CTRL + SHIFT + " .. key, Window.move_to_monitor(i), { desc = "Move to Monitor " .. i })
end
