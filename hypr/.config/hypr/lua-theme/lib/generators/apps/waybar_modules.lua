-- hypr/.config/hypr/lua-theme/lib/generators/apps/waybar_modules.lua
-- hypr/.config/hypr/lua-theme/lib/generators/waybar_modules.lua
-- Waybar basic-modules.jsonc generator from template

local Utils = require("lib.utils")
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
		["{{primary}}"] = Utils.ensure_hex(palette.theme_primary),
		["{{secondary}}"] = Utils.ensure_hex(palette.theme_secondary),
		["{{accent}}"] = Utils.ensure_hex(palette.theme_accent),
		["{{bg_core}}"] = Utils.ensure_hex(palette.bg_core),
		["{{bg_mantle}}"] = Utils.ensure_hex(palette.bg_mantle),
		["{{bg_shadow}}"] = Utils.ensure_hex(palette.bg_shadow),
		["{{bg_surface}}"] = Utils.ensure_hex(palette.bg_surface),
		["{{fg_core}}"] = Utils.ensure_hex(palette.fg_core),
		["{{fg_strong}}"] = Utils.ensure_hex(palette.fg_strong),
		["{{fg_muted}}"] = Utils.ensure_hex(palette.fg_muted),
		["{{fg_dim}}"] = Utils.ensure_hex(palette.fg_dim),
		["{{error}}"] = Utils.ensure_hex(palette.error),
		["{{warning}}"] = Utils.ensure_hex(palette.warning),
		["{{info}}"] = Utils.ensure_hex(palette.info),
		["{{hint}}"] = Utils.ensure_hex(palette.hint),
		["{{ok}}"] = Utils.ensure_hex(palette.ok),
		["{{red}}"] = Utils.ensure_hex(palette.red),
		["{{green}}"] = Utils.ensure_hex(palette.green),
		["{{blue}}"] = Utils.ensure_hex(palette.blue),
		["{{cyan}}"] = Utils.ensure_hex(palette.cyan),
		["{{magenta}}"] = Utils.ensure_hex(palette.magenta),
		["{{yellow}}"] = Utils.ensure_hex(palette.yellow),
	}

	local content = template
	for placeholder, color in pairs(replacements) do
		content = content:gsub(placeholder:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"), color)
	end

	local output_path = home .. "/.config/waybar/basic-modules.jsonc"
	return self:write_output(output_path, content)
end

return WaybarModulesGenerator
