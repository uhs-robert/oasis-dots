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
    { "A", popup("keeptabs"),      "Agents" },
    { "B", popup("bluetooth"),     "Bluetooth" },
    { "C", popup("clock"),         "Calendar" },
    { "I", popup("network"),       "Network and Internet" },
    { "M", popup("media"),         "Media" },
    { "N", popup("notifications"), "Notifications" },
    { "P", popup("battery"),       "Power and Brightness" },
    { "Q", popup("system"),        "System" },
    { "S", popup("start"),         "Start Menu" },
    { "T", popup("tray"),          "Tray" },
    { "U", popup("updates"),       "Updates" },
    { "V", popup("volume"),        "Volume" },
    { "W", popup("weather"),       "Weather" },
  },
}).setup()
