-- home/hypr/.config/hypr/extensions/auto_launcher/init.lua
local Config = require("config") ---@class Config

require("extensions.auto_launcher.launcher")

hl.bind(
  Config.leader .. " + SHIFT + O",
  hl.dsp.exec_cmd(
    "cat /tmp/hypr-sessions | rofi -i -dmenu -p Session > /tmp/hypr-session-choice && hyprctl eval 'launch_session()'"
  ),
  { description = "Workspace App Launcher" }
)
