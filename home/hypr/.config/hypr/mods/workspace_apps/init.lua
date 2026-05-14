-- mods/workspace_apps/init.lua
local Config = require("config")

hl.bind(
  Config.leader .. " + SHIFT + O",
  hl.dsp.exec_cmd("lua ~/.config/hypr/mods/workspace_apps/launcher.lua " .. Config.ws_per_monitor),
  { description = "Workspace App Launcher" }
)
