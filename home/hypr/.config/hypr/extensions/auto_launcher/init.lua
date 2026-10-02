-- home/hypr/.config/hypr/extensions/auto_launcher/init.lua
local Bind = require("lib.key.bind") ---@class BindLib
local Launcher = require("extensions.auto_launcher.launcher") ---@class Launcher

Bind.leader_key("SHIFT + O", Launcher.show_picker, "Session Launcher")
