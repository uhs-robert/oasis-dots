-- hypr/.config/hypr/theme/lib/generators/apps/swaylock.lua
-- Swaylock theme generator

local Palette = require("lib.palette")
local BaseGenerator = require("lib.generators.base")

-- Load shared utilities from lua/lib/utils.lua
local home = os.getenv("HOME")
package.path = home .. "/.config/hypr/lua/?.lua;" .. package.path
local Utils = require("lib.utils")

local SwaylockGenerator = setmetatable({}, { __index = BaseGenerator })
SwaylockGenerator.__index = SwaylockGenerator

function SwaylockGenerator:new()
	local obj = BaseGenerator:new()
	setmetatable(obj, self)
	return obj
end

-- Helper to convert hex color to swaylock format (RRGGBB without #)
local function to_swaylock_color(hex)
	local clean = Palette.ensure_hex(hex):gsub("#", "")
	return clean
end

function SwaylockGenerator:generate(palette, output_dir, palette_name)
	local home = os.getenv("HOME")
	local template_path = home .. "/.config/swaylock/config.template"
	local config_path = home .. "/.config/swaylock/config"

	-- Read template
	local template_file = io.open(template_path, "r")
	if not template_file then
		print("✗ Swaylock: Template not found at " .. template_path)
		return false
	end
	local template = template_file:read("*all")
	template_file:close()

	-- Replace placeholders with palette colors
	local content = template
		:gsub("{{BG_CORE}}", to_swaylock_color(palette.bg_core))
		:gsub("{{BG_SURFACE}}", to_swaylock_color(palette.bg_surface))
		:gsub("{{BG_MANTLE}}", to_swaylock_color(palette.bg_mantle))
		:gsub("{{FG_CORE}}", to_swaylock_color(palette.fg_core))
		:gsub("{{PRIMARY}}", to_swaylock_color(palette.theme_primary))
		:gsub("{{ORANGE}}", to_swaylock_color(palette.bright_yellow)) -- Orange color
		:gsub("{{YELLOW}}", to_swaylock_color(palette.yellow))
		:gsub("{{GREEN}}", to_swaylock_color(palette.green))
		:gsub("{{RED}}", to_swaylock_color(palette.red))

	-- Write to config file
	if Utils.write_file(config_path, content) then
		print("✓ Swaylock: Generated " .. config_path)
		return true
	end

	return false
end

return SwaylockGenerator
