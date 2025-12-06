-- hypr/.config/hypr/theme/lib/generators/yazi.lua
-- Yazi file manager theme generator

local Utils = require("lib.utils")
local BaseGenerator = require("lib.generators.base")

local YaziGenerator = setmetatable({}, { __index = BaseGenerator })
YaziGenerator.__index = YaziGenerator

function YaziGenerator:new()
	local obj = BaseGenerator:new()
	setmetatable(obj, self)
	return obj
end

function YaziGenerator:generate(palette, output_dir, palette_name)
	local home = os.getenv("HOME")
	local yazi_config_dir = home .. "/.config/yazi"
	local yazi_theme_file = yazi_config_dir .. "/theme.toml"
	local yazi_flavors_dir = yazi_config_dir .. "/flavors"

	-- Convert palette name format (e.g., "Oasis Lagoon Dark" -> "oasis-lagoon-dark")
	local flavor_name = palette_name:lower():gsub("%s+", "-")
	local flavor_dir = yazi_flavors_dir .. "/" .. flavor_name .. ".yazi"

	-- Check if flavor exists
	local flavor_check = io.open(flavor_dir .. "/flavor.toml", "r")
	if not flavor_check then
		print("⚠ Yazi: Flavor not found: " .. flavor_name)
		return false
	end
	flavor_check:close()

	-- Update theme.toml with new flavor name
	local theme_content = string.format([[# yazi/.config/yazi/theme.toml
[flavor]
dark = "%s"
]], flavor_name)

	if Utils.write_file(yazi_theme_file, theme_content) then
		print("✓ Yazi: Updated theme to: " .. flavor_name)
		Utils.write_file(output_dir .. "/yazi-flavor-name.txt", flavor_name)
		return true
	end

	return false
end

return YaziGenerator
