#!/usr/bin/env lua
-- hypr/.config/hypr/theme/main.lua
-- Theme Generator for Hyprland, Waybar, and Rofi
-- Modular architecture with separate lib files

local home = os.getenv("HOME")
local config_dir = home .. "/.config/hypr/theme"

-- Add lib directory to package path
package.path = config_dir .. "/?.lua;" .. package.path

-- Load modules
local Theme = require("lib.theme")

-- Configuration
local config = {
	config_dir = config_dir,
	palette_dir = config_dir .. "/palettes",
	output_dir = config_dir .. "/output",
	palette_name = nil
}

-- =====================================================
-- :: MAIN
-- =====================================================
local function main()
	local arg1 = arg[1]

	if arg1 == "--menu" or arg1 == "-m" then
		-- Show rofi theme picker
		Theme.show_menu(config)
	elseif arg1 == "--list" or arg1 == "-l" then
		-- List available themes
		print("Available themes:")
		for _, name in ipairs(Theme.list_palettes(config.palette_dir)) do
			local marker = (name == Theme.get_current(config.config_dir)) and " (current)" or ""
			print("  - " .. name .. marker)
		end
	elseif arg1 then
		-- Apply specific theme by name
		config.palette_name = arg1
		Theme.apply(config)
	else
		-- No argument: apply current or default
		config.palette_name = Theme.get_current(config.config_dir) or "oasis_lagoon_dark"
		Theme.apply(config)
	end
end

-- Run
main()
