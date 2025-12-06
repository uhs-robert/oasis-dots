#!/usr/bin/env lua
-- hypr/.config/hypr/lua-theme/wallpapers/day_system.lua
-- Thin CLI wrapper that delegates to wallpapers.day_system.init

local script_dir = (debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./")
local root = script_dir .. ".."

-- Ensure lua-theme root is in package.path
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local entry = require("wallpapers.day_system.init")
entry.main_cli(arg)
