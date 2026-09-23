--- Bar submap
--- Opens a Quickshell bar popup on the focused monitor, then hands keys to the popup

local Submap = require("lib.key.submap") ---@class Submap
local Cmd = require("lib.actions.cmd") ---@class Cmd

local function popup(name) return Cmd.run("qs ipc call popup open " .. name) end

Submap.define({
  name = "Bar",
  desc = "+Bar",

  escape = "reset",
  catchall = "reset",

  -- stylua: ignore
  binds = {
    { "S", popup("start"),     "Start Menu" },
    { "C", popup("clock"),     "Calendar" },
    { "V", popup("volume"),    "Volume" },
    { "B", popup("battery"),   "Battery and Brightness" },
    { "N", popup("network"),   "Network" },
    { "U", popup("bluetooth"), "Bluetooth" },
    { "Y", popup("system"),    "System" },
    { "T", popup("tray"),      "Tray" },
    { "K", popup("keeptabs"),  "Agents" },
    { "W", popup("weather"),   "Weather" },
  },
}).setup()
