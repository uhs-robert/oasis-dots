-- hypr/.config/hypr/theme/lib/generators/apps/waybar_modules.lua
-- hypr/.config/hypr/theme/lib/generators/waybar_modules.lua
-- Waybar basic-modules.jsonc generator from template

local Utils = require("lib.utils")
local Palette = require("lib.palette")
local BaseGenerator = require("lib.generators.base")

local WaybarModulesGenerator = setmetatable({}, { __index = BaseGenerator })
WaybarModulesGenerator.__index = WaybarModulesGenerator

function WaybarModulesGenerator:new()
	local obj = BaseGenerator:new()
	setmetatable(obj, self)
	return obj
end

function WaybarModulesGenerator:generate(palette, output_dir, palette_name)
	local home = os.getenv("HOME")
	local template_path = home .. "/.config/waybar/basic-modules.jsonc.template"

	-- Read template file
	local template_file = io.open(template_path, "r")
	if not template_file then
		print("✗ Could not open template: " .. template_path)
		return false
	end

	local template = template_file:read("*all")
	template_file:close()

	-- Replace placeholders with actual colors
	local replacements = {
		["{{primary}}"] = Palette.ensure_hex(palette.theme_primary),
		["{{secondary}}"] = Palette.ensure_hex(palette.theme_secondary),
		["{{accent}}"] = Palette.ensure_hex(palette.theme_accent),
		["{{bg_core}}"] = Palette.ensure_hex(palette.bg_core),
		["{{bg_mantle}}"] = Palette.ensure_hex(palette.bg_mantle),
		["{{bg_shadow}}"] = Palette.ensure_hex(palette.bg_shadow),
		["{{bg_surface}}"] = Palette.ensure_hex(palette.bg_surface),
		["{{fg_core}}"] = Palette.ensure_hex(palette.fg_core),
		["{{fg_strong}}"] = Palette.ensure_hex(palette.fg_strong),
		["{{fg_muted}}"] = Palette.ensure_hex(palette.fg_muted),
		["{{fg_dim}}"] = Palette.ensure_hex(palette.fg_dim),
		["{{error}}"] = Palette.ensure_hex(palette.error),
		["{{warning}}"] = Palette.ensure_hex(palette.warning),
		["{{info}}"] = Palette.ensure_hex(palette.info),
		["{{hint}}"] = Palette.ensure_hex(palette.hint),
		["{{ok}}"] = Palette.ensure_hex(palette.ok),
		["{{red}}"] = Palette.ensure_hex(palette.red),
		["{{green}}"] = Palette.ensure_hex(palette.green),
		["{{blue}}"] = Palette.ensure_hex(palette.blue),
		["{{cyan}}"] = Palette.ensure_hex(palette.cyan),
		["{{magenta}}"] = Palette.ensure_hex(palette.magenta),
		["{{yellow}}"] = Palette.ensure_hex(palette.yellow),
	}

	local content = template
	for placeholder, color in pairs(replacements) do
		content = content:gsub(placeholder:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"), color)
	end

	local output_path = home .. "/.config/waybar/basic-modules.jsonc"
	return self:write_output(output_path, content)
end

return WaybarModulesGenerator
