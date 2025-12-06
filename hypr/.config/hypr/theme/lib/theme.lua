-- hypr/.config/hypr/theme/lib/theme.lua
-- Theme management and switching

local Palette = require("lib.palette")
local Generators = require("lib.generators.init")

-- Load shared utilities from lua/lib/utils.lua
local home = os.getenv("HOME")
package.path = home .. "/.config/hypr/lua/?.lua;" .. package.path
local Utils = require("lib.utils")

local Theme = {}

function Theme.list_palettes(palette_dir)
	local handle = Utils.popen_assert('ls "' .. palette_dir .. '"/*.lua 2>/dev/null')
	local palettes = {}
	for file in handle:lines() do
		local name = file:match("([^/]+)%.lua$")
		if name then
			table.insert(palettes, name)
		end
	end
	handle:close()
	table.sort(palettes)
	return palettes
end

function Theme.get_current(config_dir)
	local state_file = config_dir .. "/.current_theme"
	local file = io.open(state_file, "r")
	if file then
		local theme = file:read("*line")
		file:close()
		return theme
	end
	return nil
end

function Theme.set_current(config_dir, name)
	local state_file = config_dir .. "/.current_theme"
	local file = io.open(state_file, "w")
	if file then
		file:write(name)
		file:close()
	end
end

function Theme.apply(config)
	local palette_name = config.palette_name
	local palette_dir = config.palette_dir
	local output_dir = config.output_dir
	local config_dir = config.config_dir

	print(
		"═══════════════════════════════════════"
	)
	print("  Applying Theme: " .. palette_name)
	print(
		"═══════════════════════════════════════"
	)

	-- Load palette
	print("\n→ Loading palette: " .. palette_name)
	local palette = Palette.load(palette_dir, palette_name)

	if not palette then
		print("✗ Failed to load palette")
		os.exit(1)
	end

	print("✓ Palette loaded")

	-- Generate theme files
	print("\n→ Generating theme files...")
	Generators.generate_all(palette, output_dir, palette_name)

	-- Save current theme
	Theme.set_current(config_dir, palette_name)

	-- Reload services
	print("\n→ Reloading services...")
	os.execute("hyprctl reload 2>/dev/null")
	print("✓ Hyprland reloaded")

	os.execute(
		"pkill waybar; waybar -c ~/.config/waybar/config.jsonc -s ~/.config/waybar/style.css > /dev/null 2>&1 &"
	)
	print("✓ Waybar restarted")

	-- Kitty will automatically use the updated dark-theme.auto.conf
	-- No need to kill or signal - new terminals pick it up automatically
	print("✓ Kitty: Updated dark-theme.auto.conf (open new terminal to see theme)")

	print(
		"\n═══════════════════════════════════════"
	)
	print("✓ Theme applied successfully!")
	print(
		"═══════════════════════════════════════"
	)
end

function Theme.show_menu(config)
	local palettes = Theme.list_palettes(config.palette_dir)
	if #palettes == 0 then
		print("✗ No palettes found in: " .. config.palette_dir)
		os.exit(1)
	end

	-- Build rofi menu
	local menu_items = table.concat(palettes, "\n")
	local current = Theme.get_current(config.config_dir)

	-- Use rofi to select theme
	local cmd = string.format(
		'echo -e "%s" | rofi -i -dmenu -p "Select Theme" -mesg "Current: %s"',
		menu_items,
		current or "none"
	)

	local handle = Utils.popen_assert(cmd)
	local choice = handle:read("*line")
	handle:close()

	if choice and choice ~= "" then
		config.palette_name = choice
		Theme.apply(config)
	end
end

return Theme
