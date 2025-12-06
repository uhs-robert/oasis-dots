-- hypr/.config/hypr/lua-theme/lib/generators/hyprland.lua
-- Hyprland theme generator (template-based)

local Utils = require("lib.utils")
local BaseGenerator = require("lib.generators.base")

local HyprlandGenerator = setmetatable({}, { __index = BaseGenerator })
HyprlandGenerator.__index = HyprlandGenerator

function HyprlandGenerator:new()
	local obj = BaseGenerator:new()
	setmetatable(obj, self)
	return obj
end

function HyprlandGenerator:generate(palette, output_dir, palette_name)
	local home = os.getenv("HOME")
	local template_path = home .. "/.config/hypr/hyprtheme.conf.template"

	local template_file = io.open(template_path, "r")
	if not template_file then
		print("✗ Could not open template: " .. template_path)
		return false
	end

	local template = template_file:read("*all")
	template_file:close()

	-- Allow both Hypr-formatted and hex placeholders so the template stays flexible
	local replacements = {
		["{{bg_core_hypr}}"] = Utils.hex_to_hypr(palette.bg_core),
		["{{bg_mantle_hypr}}"] = Utils.hex_to_hypr(palette.bg_mantle),
		["{{bg_shadow_hypr}}"] = Utils.hex_to_hypr(palette.bg_shadow),
		["{{bg_surface_hypr}}"] = Utils.hex_to_hypr(palette.bg_surface),
		["{{fg_core_hypr}}"] = Utils.hex_to_hypr(palette.fg_core),
		["{{fg_strong_hypr}}"] = Utils.hex_to_hypr(palette.fg_strong),
		["{{fg_muted_hypr}}"] = Utils.hex_to_hypr(palette.fg_muted),
		["{{fg_dim_hypr}}"] = Utils.hex_to_hypr(palette.fg_dim or palette.fg_muted),
		["{{primary_hypr}}"] = Utils.hex_to_hypr(palette.theme_primary),
		["{{secondary_hypr}}"] = Utils.hex_to_hypr(palette.theme_secondary),
		["{{accent_hypr}}"] = Utils.hex_to_hypr(palette.theme_accent),
		["{{error_hypr}}"] = Utils.hex_to_hypr(palette.error),
		["{{warning_hypr}}"] = Utils.hex_to_hypr(palette.warning),
		["{{info_hypr}}"] = Utils.hex_to_hypr(palette.info),
		["{{hint_hypr}}"] = Utils.hex_to_hypr(palette.hint),
		["{{ok_hypr}}"] = Utils.hex_to_hypr(palette.ok),
		["{{red_hypr}}"] = Utils.hex_to_hypr(palette.red),
		["{{green_hypr}}"] = Utils.hex_to_hypr(palette.green),
		["{{blue_hypr}}"] = Utils.hex_to_hypr(palette.blue),
		["{{cyan_hypr}}"] = Utils.hex_to_hypr(palette.cyan),
		["{{magenta_hypr}}"] = Utils.hex_to_hypr(palette.magenta),
		["{{yellow_hypr}}"] = Utils.hex_to_hypr(palette.yellow),

		-- Hex variants for use elsewhere in the template if desired
		["{{bg_core}}"] = Utils.ensure_hex(palette.bg_core),
		["{{bg_mantle}}"] = Utils.ensure_hex(palette.bg_mantle),
		["{{bg_shadow}}"] = Utils.ensure_hex(palette.bg_shadow),
		["{{bg_surface}}"] = Utils.ensure_hex(palette.bg_surface),
		["{{fg_core}}"] = Utils.ensure_hex(palette.fg_core),
		["{{fg_strong}}"] = Utils.ensure_hex(palette.fg_strong),
		["{{fg_muted}}"] = Utils.ensure_hex(palette.fg_muted),
		["{{fg_dim}}"] = Utils.ensure_hex(palette.fg_dim or palette.fg_muted),
		["{{primary}}"] = Utils.ensure_hex(palette.theme_primary),
		["{{secondary}}"] = Utils.ensure_hex(palette.theme_secondary),
		["{{accent}}"] = Utils.ensure_hex(palette.theme_accent),
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
	for placeholder, value in pairs(replacements) do
		local escaped = placeholder:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
		content = content:gsub(escaped, value)
	end

	local output_path = output_dir .. "/hyprtheme.conf"
	return self:write_output(output_path, content)
end

return HyprlandGenerator
