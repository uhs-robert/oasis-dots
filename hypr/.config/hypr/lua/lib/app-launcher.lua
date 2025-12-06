-- hypr/.config/hypr/lua/lib/app-launcher.lua
-- Application launching with workspace management

local Logger = require("lib.logger")
local Hyprctl = require("lib.hyprctl")
local AppTypes = require("lib.app-types")
local Wait = require("lib.wait")
local Utils = require("lib.utils")
local Settings = require("config.settings")

local AppLauncher = {}

-- Launch a single application on a specific workspace
-- app: { cmd = "command", monitor = "...", increment = bool }
-- workspace: workspace number to launch on
function AppLauncher.launch(app, workspace)
	local cmd = app.cmd
	local app_type = AppTypes.detect(cmd)

	-- Flatpak apps don't use workspace rules (they manage their own windows)
	if app_type == "flatpak" then
		Logger.info("Launching flatpak: " .. cmd)
		Hyprctl.exec(cmd)
	else
		local exec_cmd = string.format("[workspace %d silent] %s", workspace, cmd)
		Logger.info("Launching: " .. exec_cmd)
		Hyprctl.exec(exec_cmd)
	end

	-- Small delay between launches to avoid race conditions
	Utils.sleep(Settings.DELAYS.between_launches)
end

-- Launch Firefox and distribute windows across multiple workspaces
-- workspaces: array of workspace numbers for Firefox windows
-- url: optional URL for first window
-- Returns: true on success, false on failure
function AppLauncher.launch_firefox_distributed(workspaces, url)
	if #workspaces == 0 then
		Logger.debug("No Firefox windows to launch")
		return true
	end

	Logger.info(string.format("Launching Firefox with %d expected windows", #workspaces))

	-- Determine command (with or without URL)
	local cmd = url and ("firefox " .. url) or "firefox"

	-- Launch Firefox on first workspace
	local exec_cmd = string.format("[workspace %d silent] %s", workspaces[1], cmd)
	Logger.info("Launching: " .. exec_cmd)
	Hyprctl.exec(exec_cmd)

	-- Wait for Firefox windows to appear
	local window_class = Settings.WINDOW_CLASSES.firefox
	local firefox_windows = Wait.for_windows_by_class(window_class, #workspaces)

	if #firefox_windows < #workspaces then
		Logger.warn(string.format("Only found %d Firefox windows (expected %d)", #firefox_windows, #workspaces))
		return false
	end

	-- Distribute Firefox windows to assigned workspaces
	for i, ws in ipairs(workspaces) do
		local addr = firefox_windows[i]
		if addr then
			Logger.info(string.format("Moving Firefox window %s to workspace %d", addr, ws))
			Hyprctl.focus_window(addr)
			Hyprctl.move_to_workspace_silent(ws)
		end
	end

	return true
end

-- Launch multiple applications across workspaces
-- apps: array of app specifications
-- workspace_assignments: array mapping app index to workspace number
function AppLauncher.launch_batch(apps, workspace_assignments)
	Logger.info("Launching applications...")

	for i, app in ipairs(apps) do
		local ws = workspace_assignments[i]
		if ws then
			AppLauncher.launch(app, ws)
		else
			Logger.warn(string.format("No workspace for app #%d: %s", i, app.cmd))
		end
	end
end

-- Preload workspaces to ensure proper window placement
-- workspace_assignments: array of workspace numbers
function AppLauncher.preload_workspaces(workspace_assignments)
	Logger.info("Preloading workspaces...")
	local seen = {}

	for _, ws in pairs(workspace_assignments) do
		if not seen[ws] then
			seen[ws] = true
			Logger.debug("Preloading workspace " .. ws)
			Hyprctl.focus_workspace(ws)
			Utils.sleep(Settings.DELAYS.workspace_preload)
		end
	end

	-- Return to workspace 1
	Hyprctl.focus_workspace(1)
end

return AppLauncher
