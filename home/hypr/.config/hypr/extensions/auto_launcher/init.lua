-- home/hypr/.config/hypr/extensions/auto_launcher/init.lua
local Config = require("config") ---@class Config
local Launcher = require("extensions.auto_launcher.launcher") ---@class Launcher

hl.bind(Config.leader .. " + SHIFT + O", Launcher.show_picker, { description = "Workspace App Launcher" })
