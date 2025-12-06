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
local Process = require("lib.process")
local AppTypes = require("lib.app-types")
local AppLauncher = require("lib.app-launcher")
local WorkspaceAllocator = require("lib.workspace-allocator")
local Menu = require("lib.menu")
local Wait = require("lib.wait")

-- Load configuration
local AppConfig = require("config.app-setups")

-- Set logger tag
Logger.set_tag("hypr-launcher")

-- ========== GLOBALS ========== --

local IS_STARTUP = false
local allocator = WorkspaceAllocator.new()
local workspace_assignments = {}

-- ========== APP PROCESSING ========== --

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
-- Returns: workspace_assignments table, firefox_workspaces array
local function resolve_workspace_assignments(apps)
	local assignments = {}
	local firefox_workspaces = {}

	for i, app in ipairs(apps) do
		local monitor = app.monitor
		local increment = app.increment or false

		local ws = allocator:get_next(monitor, increment)
		if ws then
			assignments[i] = ws

			-- Track Firefox workspaces for special handling
			if AppTypes.is_firefox(app.cmd) then
				table.insert(firefox_workspaces, ws)
			end

			Logger.debug(string.format("Resolved app #%d (%s) -> workspace %d", i, app.cmd, ws))
		else
			Logger.warn(string.format("Failed to resolve workspace for app #%d", i))
		end
	end

	return assignments, firefox_workspaces
end

-- ========== APP LAUNCHING ========== --

-- Launch all non-multi-window applications
local function launch_standard_apps(apps, assignments)
	Logger.info("Launching standard applications...")

	for i, app in ipairs(apps) do
		local ws = assignments[i]

		-- Skip multi-window apps (handled separately)
		if AppTypes.is_multi_window(app.cmd) then
			goto continue
		end

		if ws then
			AppLauncher.launch(app, ws)
		else
			Logger.warn(string.format("No workspace for app #%d: %s", i, app.cmd))
		end

		::continue::
	end
end

-- Handle multi-window applications (Firefox, Chrome, etc.)
local function handle_multi_window_apps(apps, firefox_workspaces)
	if #firefox_workspaces == 0 then
		return
	end

	-- Find first Firefox command (might have URL)
	local first_url = nil
	for _, app in ipairs(apps) do
		if AppTypes.is_firefox(app.cmd) then
			-- Extract URL if present
			local url = app.cmd:match("^firefox%s+(.+)$")
			if url then
				first_url = url
				break
			end
		end
	end

	-- Launch Firefox distributed across workspaces
	AppLauncher.launch_firefox_distributed(firefox_workspaces, first_url)
end

-- ========== MENU & SELECTION ========== --

-- Show menu and get user's setup selection
local function select_setup()
	Logger.info("Prompting user for setup selection...")

	-- Build menu items from config
	local items = {}
	for name, _ in pairs(AppConfig.setups) do
		table.insert(items, name)
	end

	-- Show menu (optionally on primary monitor if startup)
	local monitor = IS_STARTUP and 0 or nil
	local choice = Menu.select(items, "Select session", monitor)

	if choice then
		Logger.info("User selected: " .. choice)
	else
		Logger.info("User cancelled selection")
	end

	return choice
end

-- ========== MAIN LAUNCHER ========== --

-- Launch a complete setup by name
local function launch_setup(setup_name)
	local setup_def = AppConfig.setups[setup_name]
	if not setup_def then
		Logger.error("Unknown setup: " .. setup_name)
		return false
	end

	-- Reset allocator state for new launch
	allocator:reset()

	-- Flatten and resolve apps
	local apps = flatten_apps(setup_def)
	local assignments, firefox_workspaces = resolve_workspace_assignments(apps)
	workspace_assignments = assignments

	Logger.info(string.format("Launching setup '%s' with %d apps", setup_name, #apps))

	-- Execute launch sequence
	AppLauncher.preload_workspaces(assignments)
	launch_standard_apps(apps, assignments)
	handle_multi_window_apps(apps, firefox_workspaces)

	return true
end

-- ========== CLEANUP ========== --

-- Cleanup routine (runs on exit)
local function cleanup()
	Logger.debug("Exiting session selection...")
	if IS_STARTUP then
		-- Wait for all windows to appear before returning to workspace 1
		Wait.for_window_count(#workspace_assignments)
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

	-- Register cleanup
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
end

-- Run main and ensure cleanup runs
local status, err = pcall(main)
if not status then
	Logger.error("Error in main: " .. tostring(err))
end
Process.run_cleanup()
