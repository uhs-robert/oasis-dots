-- home/hypr/.config/hypr/extensions/wallpaper/init.lua
-- CLI entry point for the wallpaper system

-- Ensure theme root is in package.path
local script_dir = (debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./")
local root = script_dir .. ".."
local hypr_root = root .. "/.."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. hypr_root .. "/?.lua;" .. package.path

local Rotate = require("wallpaper.lib.rotate") ---@class Rotate
Rotate.init(arg)
