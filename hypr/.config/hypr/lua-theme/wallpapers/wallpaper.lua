#!/usr/bin/env lua
-- hypr/.config/hypr/lua-theme/wallpapers/wallpaper.lua
-- CLI entry point for the wallpaper system

local script_dir = (debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./")
local root = script_dir .. ".."

-- Ensure lua-theme root is in package.path
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local Rotate = require("wallpapers.lib.rotate")
Rotate.main_cli(arg)
