local Bind = require("lib.key.bind")
local Config = require("config")
local Window = require("lib.actions.window")
local Workspace = require("lib.actions.workspace")

local function universal(description) return { submap_universal = true, desc = description } end

-- stylua: ignore start
Bind.leader_key("ESCAPE",    hl.dsp.submap("reset"), universal("Reset Submaps"))
Bind.leader_cmd("SLASH",     require("lib.scripts").keybind_help, universal("Keybind Help"))

Bind.leader_key("C",         Window.close(),             { desc = "Close Window" })
Bind.leader_key("F",         Window.fullscreen_toggle(), { desc = "Toggle Fullscreen" })
Bind.leader_key("TAB",       Workspace.focus_last(),     { desc = "Go to Last Active WS" })

Bind.leader_key({ "H", "LEFT" },  Window.focus_dir("l"), "Focus Left",  { submap_universal = true })
Bind.leader_key({ "L", "RIGHT" }, Window.focus_dir("r"), "Focus Right", { submap_universal = true })
Bind.leader_key({ "K", "UP" },    Window.focus_dir("u"), "Focus Up",    { submap_universal = true })
Bind.leader_key({ "J", "DOWN" },  Window.focus_dir("d"), "Focus Down",  { submap_universal = true })

Bind.leader_key("S",         Window.toggle_special("scratchpad"), universal("Toggle Scratchpad"))
Bind.leader_key("SHIFT + S", Window.move_to_special("scratchpad"), universal("Move to Scratchpad"))

for i = 1, math.max(#Config.monitors, 10) do
  local key = i % 10
  Bind.leader_key("CTRL + " .. key,         Window.focus_monitor(i),  { desc = "Focus Monitor " .. i })
  Bind.leader_key("CTRL + SHIFT + " .. key, Window.move_to_monitor(i), { desc = "Move to Monitor " .. i })
end

Bind.leader_key({ "SHIFT + H", "SHIFT + LEFT" },  Window.move_dir("l"), "Move Window Left",  { submap_universal = true })
Bind.leader_key({ "SHIFT + L", "SHIFT + RIGHT" }, Window.move_dir("r"), "Move Window Right", { submap_universal = true })
Bind.leader_key({ "SHIFT + K", "SHIFT + UP" },    Window.move_dir("u"), "Move Window Up",    { submap_universal = true })
Bind.leader_key({ "SHIFT + J", "SHIFT + DOWN" },  Window.move_dir("d"), "Move Window Down",  { submap_universal = true })
