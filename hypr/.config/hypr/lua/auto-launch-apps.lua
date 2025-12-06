#!/usr/bin/env lua
-- hypr/.config/hypr/lua/auto-launch-apps.lua
-- Interactive launcher for pre-configured application setups

local home = os.getenv("HOME")
local config_dir = home .. "/.config/hypr/lua"

-- Add lib directory to package path
package.path = config_dir .. "/?.lua;" .. package.path

-- Load modules
local Logger = require("lib.logger")
local Hyprctl = require("lib.hyprctl")
local Monitor = require("lib.monitor")
local Process = require("lib.process")
local Utils = require("lib.utils")

-- Load configuration
local AppConfig = require("config.app-setups")

-- Set logger tag
Logger.set_tag("hypr-launcher")

-- ========== GLOBALS ========== --

local IS_STARTUP = false
local workspace_assignments = {}  -- Resolved workspace assignments for apps
local firefox_workspaces = {}     -- Track Firefox window assignments

-- Runtime tracking for workspace allocation
local monitor_current_ws = {}  -- Current workspace per monitor name
local workspace_usage = {}     -- Number of apps assigned to each workspace

-- ========== WORKSPACE RESOLUTION ========== --

-- Get next available workspace on a monitor
-- Returns: workspace number
local function get_next_workspace(monitor_name, force_increment)
	local start_ws, end_ws = Monitor.get_workspace_range(monitor_name)
	if not start_ws then
		Logger.error("Failed to get workspace range for monitor: " .. monitor_name)
		return nil
	end

	local current_ws = monitor_current_ws[monitor_name] or start_ws

	if force_increment then
		-- For + syntax: always increment to next workspace after first use
		if not monitor_current_ws[monitor_name] then
			-- First assignment for this monitor - use first workspace in range
			current_ws = start_ws
			Logger.debug(string.format("First assignment on monitor %s, using workspace %d",
				monitor_name, current_ws))
		else
			-- Subsequent assignments - always increment
			local prev_ws = current_ws
			current_ws = current_ws + 1
			if current_ws > end_ws then
				current_ws = start_ws  -- Wrap around
			end
			Logger.debug(string.format("Incrementing from workspace %d to %d on monitor %s",
				prev_ws, current_ws, monitor_name))
		end
	else
		-- Non-increment behavior (fallback)
		if not monitor_current_ws[monitor_name] then
			current_ws = start_ws
		end
	end

	-- Update tracking
	monitor_current_ws[monitor_name] = current_ws
	workspace_usage[current_ws] = (workspace_usage[current_ws] or 0) + 1

	Logger.info(string.format("Assigned workspace %d on monitor %s (usage: %d)",
		current_ws, monitor_name, workspace_usage[current_ws]))

	return current_ws
end

-- Flatten nested app definitions into a single list
local function flatten_apps(setup_list)
	local flattened = {}

	for _, item in ipairs(setup_list) do
		-- Check if item is a nested table (app block like firefox_triple)
		if item[1] and type(item[1]) == "table" and item[1].monitor then
			-- This is an app block with multiple entries
			for _, app in ipairs(item) do
				table.insert(flattened, app)
			end
		else
			-- Single app definition
			table.insert(flattened, item)
		end
	end

	return flattened
end

-- Resolve monitor assignments to actual workspaces
local function resolve_workspace_assignments(apps)
	local assignments = {}
	firefox_workspaces = {}

	for i, app in ipairs(apps) do
		local monitor = app.monitor
		local increment = app.increment or false

		local ws = get_next_workspace(monitor, increment)
		if ws then
			assignments[i] = ws
			if app.cmd == "firefox" or app.cmd:match("^firefox ") then
				table.insert(firefox_workspaces, ws)
			end
			Logger.debug(string.format("Resolved app #%d (%s) -> workspace %d",
				i, app.cmd, ws))
		else
			Logger.warn(string.format("Failed to resolve workspace for app #%d", i))
		end
	end

	return assignments
end

-- ========== WORKSPACE & APP LAUNCHING ========== --

-- Preload all required workspaces to ensure proper window placement
local function preload_workspaces(assignments)
	Logger.info("Preloading workspaces...")
	local seen = {}

	for _, ws in pairs(assignments) do
		if not seen[ws] then
			seen[ws] = true
			Logger.debug("Preloading workspace " .. ws)
			Hyprctl.focus_workspace(ws)
			Utils.sleep(0.1)
		end
	end

	Hyprctl.focus_workspace(1)
end

-- Launch all non-Firefox applications
local function launch_non_firefox_apps(apps, assignments)
	Logger.info("Launching non-Firefox applications...")

	for i, app in ipairs(apps) do
		local cmd = app.cmd
		local ws = assignments[i]

		-- Skip Firefox (handled separately)
		if cmd == "firefox" or cmd:match("^firefox ") then
			goto continue
		end

		if ws then
			-- Flatpak apps don't use workspace rules (they manage their own windows)
			if cmd:match("^flatpak run") then
				Logger.info("Launching: " .. cmd)
				Hyprctl.exec(cmd)
			else
				local exec_cmd = string.format("[workspace %d silent] %s", ws, cmd)
				Logger.info("Launching: " .. exec_cmd)
				Hyprctl.exec(exec_cmd)
			end

			-- Small delay between launches to avoid race conditions
			Utils.sleep(0.1)
		else
			Logger.warn(string.format("No workspace for app #%d: %s", i, cmd))
		end

		::continue::
	end
end

-- Handle Firefox windows and distribute to workspaces
local function handle_firefox(apps)
	if #firefox_workspaces == 0 then
		Logger.debug("No Firefox windows to launch")
		return
	end

	Logger.info(string.format("Launching Firefox with %d expected windows", #firefox_workspaces))

	-- Find first Firefox command (might have URL)
	local first_firefox_cmd = "firefox"
	for _, app in ipairs(apps) do
		if app.cmd == "firefox" or app.cmd:match("^firefox ") then
			first_firefox_cmd = app.cmd
			break
		end
	end

	-- Launch Firefox on first workspace
	local exec_cmd = string.format("[workspace %d silent] %s",
		firefox_workspaces[1], first_firefox_cmd)
	Logger.info("Launching: " .. exec_cmd)
	Hyprctl.exec(exec_cmd)

	-- Wait for Firefox windows to appear
	local expected = #firefox_workspaces
	local timeout = 10
	local elapsed = 0
	local firefox_windows = {}

	while elapsed < timeout do
		local clients_json = Hyprctl.clients()
		if clients_json then
			local query = '.[] | select(.class=="org.mozilla.firefox") | .address'
			firefox_windows = Hyprctl.query_json_lines(clients_json, query)

			Logger.debug(string.format("Waiting for Firefox windows... found %d of %d",
				#firefox_windows, expected))

			if #firefox_windows >= expected then
				break
			end
		end

		Utils.sleep(1)
		elapsed = elapsed + 1
	end

	if #firefox_windows < expected then
		Logger.warn(string.format("Only found %d Firefox windows after %d seconds (expected %d)",
			#firefox_windows, elapsed, expected))
	end

	-- Distribute Firefox windows to assigned workspaces
	for i, ws in ipairs(firefox_workspaces) do
		local addr = firefox_windows[i]
		if addr then
			Logger.info(string.format("Moving Firefox window %s to workspace %d", addr, ws))
			Hyprctl.focus_window(addr)
			Hyprctl.move_to_workspace_silent(ws)
		end
	end
end

-- Wait for all expected windows to appear (startup only)
local function wait_for_windows(expected_count)
	Logger.info(string.format("Waiting for %d windows to appear...", expected_count))

	local timeout = 10
	local elapsed = 0

	while elapsed < timeout do
		local clients_json = Hyprctl.clients()
		if clients_json then
			local count_str = Hyprctl.query_json(clients_json, '. | length')
			local count = tonumber(count_str) or 0

			if count >= expected_count then
				Logger.info(string.format("Detected %d windows of %d expected", count, expected_count))
				return
			end
		end

		Utils.sleep(1)
		elapsed = elapsed + 1
	end

	Logger.warn(string.format("Timeout: only detected windows after %d seconds", elapsed))
end

-- ========== MENU & SELECTION ========== --

-- Show rofi menu to select a setup
local function select_setup()
	Logger.info("Prompting user for setup selection...")

	-- Build menu items
	local items = {}
	for name, _ in pairs(AppConfig.setups) do
		table.insert(items, name)
	end
	table.sort(items)

	local menu_str = table.concat(items, "\n")

	-- Build rofi command
	local rofi_cmd
	if IS_STARTUP then
		-- Show on primary monitor (workspace 1)
		Hyprctl.focus_workspace(1)
		Utils.sleep(0.1)
		rofi_cmd = string.format('echo "%s" | ROFI_MONITOR=0 rofi -i -dmenu -p "Select session"',
			menu_str)
	else
		rofi_cmd = string.format('echo "%s" | rofi -i -dmenu -p "Select session"', menu_str)
	end

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

-- ========== MAIN LAUNCHER ========== --

local function launch_setup(setup_name)
	local setup_def = AppConfig.setups[setup_name]
	if not setup_def then
		Logger.error("Unknown setup: " .. setup_name)
		return false
	end

	-- Reset tracking
	monitor_current_ws = {}
	workspace_usage = {}
	workspace_assignments = {}
	firefox_workspaces = {}

	-- Flatten and resolve apps
	local apps = flatten_apps(setup_def)
	workspace_assignments = resolve_workspace_assignments(apps)

	Logger.info(string.format("Launching setup '%s' with %d apps", setup_name, #apps))

	-- Execute launch sequence
	preload_workspaces(workspace_assignments)
	launch_non_firefox_apps(apps, workspace_assignments)
	handle_firefox(apps)

	return true
end

-- Cleanup routine (runs on exit)
local function cleanup()
	Logger.debug("Exiting session selection...")
	if IS_STARTUP then
		wait_for_windows(#workspace_assignments)
		Hyprctl.focus_monitor(0)
		Hyprctl.focus_workspace(1)
	end
end

-- ========== ENTRY POINT ========== --

local function main()
	-- Parse arguments
	if arg[1] == "--startup" then
		IS_STARTUP = true
	end

	-- Register cleanup (will run automatically on script exit)
	Process.cleanup_on_exit(cleanup)

	-- Show menu and launch selected setup
	local choice = select_setup()
	if not choice then
		Logger.info("No setup selected, exiting")
		os.exit(0)
	end

	local success = launch_setup(choice)
	if not success then
		Logger.error("Failed to launch setup")
		os.exit(1)
	end

	Logger.info("Setup launched successfully")
	-- cleanup() will be called automatically by Process.run_cleanup()
end

-- Run main and ensure cleanup runs
local status, err = pcall(main)
if not status then
	Logger.error("Error in main: " .. tostring(err))
end
Process.run_cleanup()
