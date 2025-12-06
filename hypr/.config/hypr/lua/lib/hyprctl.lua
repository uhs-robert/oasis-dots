-- hypr/.config/hypr/lua/lib/hyprctl.lua
-- Wrapper for Hyprland IPC via hyprctl

local Logger = require("lib.logger")
local Utils = require("lib.utils")

local Hyprctl = {}

-- Execute hyprctl command and return output
local function exec(args)
	local cmd = "hyprctl " .. args .. " 2>&1"
	local handle = Utils.popen_assert(cmd)
	local output = handle:read("*a")
	handle:close()
	return output
end

-- Parse JSON output using jq (fallback for pure Lua JSON parsing)
local function parse_json(json_str)
	-- Write JSON to temp file
	local tmp_file = os.tmpname()
	local success = Utils.write_file(tmp_file, json_str)
	if not success then
		Logger.error("Failed to create temp file for JSON parsing")
		return nil
	end

	-- Use jq to parse and re-output (validates JSON)
	local handle = Utils.popen_assert("jq '.' " .. tmp_file .. " 2>&1")
	local output = handle:read("*a")
	local parse_success = handle:close()
	os.remove(tmp_file)

	if not parse_success then
		Logger.error("jq parsing failed")
		return nil
	end

	-- For now, we'll work with JSON as strings and use jq for queries
	-- In future, could integrate lua-cjson or dkjson for native parsing
	return output
end

-- Get monitors as JSON string (use jq to query fields)
function Hyprctl.monitors()
	local output = exec("monitors -j")
	if not output then
		return nil
	end
	return output
end

-- Get workspaces as JSON string
function Hyprctl.workspaces()
	local output = exec("workspaces -j")
	if not output then
		return nil
	end
	return output
end

-- Get clients (windows) as JSON string
function Hyprctl.clients()
	local output = exec("clients -j")
	if not output then
		return nil
	end
	return output
end

-- Query JSON with jq and return result
-- Example: query_json(monitors_json, '.[] | select(.id==0) | .name')
function Hyprctl.query_json(json_str, jq_query)
	local tmp_file = os.tmpname()
	local success = Utils.write_file(tmp_file, json_str)
	if not success then
		Logger.error("Failed to create temp file for jq query")
		return nil
	end

	local cmd = string.format("jq -r '%s' %s 2>&1", jq_query, tmp_file)
	local handle = Utils.popen_assert(cmd)
	local output = handle:read("*a")
	handle:close()
	os.remove(tmp_file)

	-- Trim trailing newline
	return output:gsub("\n$", "")
end

-- Query JSON and return lines as array
function Hyprctl.query_json_lines(json_str, jq_query)
	local result = Hyprctl.query_json(json_str, jq_query)
	if not result or result == "" then
		return {}
	end

	local lines = {}
	for line in result:gmatch("[^\n]+") do
		table.insert(lines, line)
	end
	return lines
end

-- Dispatch a hyprctl command
-- Example: dispatch("workspace", "1")
-- Example: dispatch("exec", "[workspace 1 silent] firefox")
function Hyprctl.dispatch(command, args)
	args = args or ""

	-- For exec commands, we need to properly quote the entire argument
	local cmd_str
	if command == "exec" then
		-- Escape any quotes in args and wrap in quotes
		local escaped_args = args:gsub('"', '\\"')
		cmd_str = string.format('dispatch %s "%s"', command, escaped_args)
	else
		cmd_str = string.format("dispatch %s %s", command, args)
	end

	Logger.debug("hyprctl " .. cmd_str)
	local output = exec(cmd_str)
	if not output then
		Logger.error("Dispatch failed: " .. cmd_str)
		return false
	end
	return true
end

-- Focus a monitor by ID
function Hyprctl.focus_monitor(monitor_id)
	return Hyprctl.dispatch("focusmonitor", tostring(monitor_id))
end

-- Move workspace to monitor
function Hyprctl.move_workspace_to_monitor(workspace, monitor_id)
	return Hyprctl.dispatch("moveworkspacetomonitor", workspace .. " " .. monitor_id)
end

-- Focus workspace
function Hyprctl.focus_workspace(workspace)
	return Hyprctl.dispatch("workspace", tostring(workspace))
end

-- Execute command
function Hyprctl.exec(command)
	return Hyprctl.dispatch("exec", command)
end

-- Focus window by address
function Hyprctl.focus_window(address)
	return Hyprctl.dispatch("focuswindow", "address:" .. address)
end

-- Move window to workspace silently
function Hyprctl.move_to_workspace_silent(workspace)
	return Hyprctl.dispatch("movetoworkspacesilent", tostring(workspace))
end

-- Reload Hyprland configuration
function Hyprctl.reload()
	exec("reload")
	Logger.info("Hyprland configuration reloaded")
end

return Hyprctl
