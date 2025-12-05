-- hypr/.config/hypr/lua-theme/lib/generators/init.lua
-- Generator registry - loads and manages all app generators

local Generators = {
	hyprland = require("lib.generators.apps.hyprland"):new(),
	waybar = require("lib.generators.apps.waybar"):new(),
	rofi = require("lib.generators.apps.rofi"):new(),
	kitty = require("lib.generators.apps.kitty"):new(),
}

-- Generate all themes
function Generators.generate_all(palette, output_dir, palette_name)
	Generators.hyprland:generate(palette, output_dir, palette_name)
	Generators.waybar:generate(palette, output_dir, palette_name)
	Generators.rofi:generate(palette, output_dir, palette_name)
	Generators.kitty:generate(palette, output_dir, palette_name)
end

return Generators
