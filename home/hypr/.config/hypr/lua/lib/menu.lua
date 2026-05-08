-- hypr/.config/hypr/lua/lib/menu.lua
-- Rofi menu integration

local Logger = require("lib.logger")
local Hyprctl = require("lib.hyprctl")
local Utils = require("lib.utils")
local Settings = require("config.settings")

local Menu = {}

-- Show rofi menu and return user selection
-- items: array of menu items (strings)
-- prompt: prompt text for the menu
-- monitor: optional monitor number to show menu on (0-indexed)
-- Returns: selected item or nil if cancelled
function Menu.select(items, prompt, monitor)
	if #items == 0 then
		Logger.warn("No items provided to menu")
		return nil
	end

	-- Sort items for consistent display
	local sorted_items = {}
	for _, item in ipairs(items) do
		table.insert(sorted_items, item)
	end
	table.sort(sorted_items)

	local menu_str = table.concat(sorted_items, "\n")

	-- Build rofi command
	local rofi_cmd
	if monitor ~= nil then
		-- Show on specific monitor (prepare workspace)
		Hyprctl.focus_workspace(1)
		Utils.sleep(Settings.DELAYS.menu_focus)
		rofi_cmd = string.format('echo "%s" | ROFI_MONITOR=%d rofi -i -dmenu -p "%s"', menu_str, monitor, prompt)
	else
		rofi_cmd = string.format('echo "%s" | rofi -i -dmenu -p "%s"', menu_str, prompt)
	end

	Logger.debug("Showing rofi menu: " .. prompt)
	local handle = Utils.popen_assert(rofi_cmd)
	local choice = handle:read("*line")
	handle:close()

	if choice and choice ~= "" then
		Logger.info("User selected: " .. choice)
		return choice
	else
		Logger.info("User cancelled selection")
		return nil
	end
end

-- Show multi-select rofi menu
-- items: array of menu items (strings)
-- prompt: prompt text for the menu
-- Returns: array of selected items or empty array if cancelled
function Menu.multi_select(items, prompt)
	if #items == 0 then
		Logger.warn("No items provided to menu")
		return {}
	end

	local sorted_items = {}
	for _, item in ipairs(items) do
		table.insert(sorted_items, item)
	end
	table.sort(sorted_items)

	local menu_str = table.concat(sorted_items, "\n")

	-- Use rofi in multi-select mode
	local rofi_cmd = string.format('echo "%s" | rofi -i -dmenu -multi-select -p "%s"', menu_str, prompt)

	Logger.debug("Showing rofi multi-select menu: " .. prompt)
	local handle = Utils.popen_assert(rofi_cmd)
	local output = handle:read("*a")
	handle:close()

	if not output or output == "" then
		Logger.info("User cancelled multi-selection")
		return {}
	end

	-- Parse selected items (one per line)
	local selected = {}
	for line in output:gmatch("[^\n]+") do
		table.insert(selected, line)
	end

	Logger.info(string.format("User selected %d items", #selected))
	return selected
end

-- Show confirmation dialog
-- message: message to display
-- Returns: true if confirmed, false if cancelled
function Menu.confirm(message)
	local items = { "Yes", "No" }
	local choice = Menu.select(items, message)
	return choice == "Yes"
end

return Menu
