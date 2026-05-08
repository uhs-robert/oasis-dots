-- hypr/.config/hypr/lua/lib/monitor.lua
-- Monitor workspace range calculations

local Logger = require("lib.logger")

local Monitor = {}

-- Load monitor configuration
local MonitorConfig = require("config.monitors")
Monitor.MONITOR_MAP = MonitorConfig.MONITOR_MAP

-- Get workspace range for a monitor name (PRIMARY, LEFT, RIGHT, CENTER)
-- Returns: start_ws, end_ws
function Monitor.get_workspace_range(monitor_name)
	local workspace_group = Monitor.MONITOR_MAP[monitor_name]
	if not workspace_group then
		Logger.error("Unknown monitor name: " .. monitor_name)
		return nil, nil
	end

	local start_ws = workspace_group * 5 + 1
	local end_ws = workspace_group * 5 + 5

	return start_ws, end_ws
end

return Monitor
