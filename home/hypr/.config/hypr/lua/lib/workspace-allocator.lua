-- hypr/.config/hypr/lua/lib/workspace-allocator.lua
-- Stateful workspace allocation for app launching

local Logger = require("lib.logger")
local Monitor = require("lib.monitor")

local WorkspaceAllocator = {}
WorkspaceAllocator.__index = WorkspaceAllocator

-- Create a new workspace allocator instance
function WorkspaceAllocator.new()
	local self = setmetatable({}, WorkspaceAllocator)
	self.monitor_current_ws = {} -- Track current workspace per monitor
	self.workspace_usage = {} -- Track number of apps per workspace
	return self
end

-- Reset allocation state
function WorkspaceAllocator:reset()
	self.monitor_current_ws = {}
	self.workspace_usage = {}
end

-- Get next available workspace on a monitor
-- monitor_name: monitor name (PRIMARY, LEFT, RIGHT, CENTER)
-- force_increment: if true, always increment workspace (for + syntax)
-- Returns: workspace number or nil on error
function WorkspaceAllocator:get_next(monitor_name, force_increment)
	local start_ws, end_ws = Monitor.get_workspace_range(monitor_name)
	if not start_ws then
		Logger.error("Failed to get workspace range for monitor: " .. monitor_name)
		return nil
	end

	local current_ws = self.monitor_current_ws[monitor_name] or start_ws

	if force_increment then
		-- For + syntax: always increment to next workspace after first use
		if not self.monitor_current_ws[monitor_name] then
			-- First assignment for this monitor - use first workspace in range
			current_ws = start_ws
			Logger.debug(string.format("First assignment on monitor %s, using workspace %d", monitor_name, current_ws))
		else
			-- Subsequent assignments - always increment
			local prev_ws = current_ws
			current_ws = current_ws + 1
			if current_ws > end_ws then
				current_ws = start_ws -- Wrap around
			end
			Logger.debug(
				string.format("Incrementing from workspace %d to %d on monitor %s", prev_ws, current_ws, monitor_name)
			)
		end
	else
		-- Non-increment behavior (fallback)
		if not self.monitor_current_ws[monitor_name] then
			current_ws = start_ws
		end
	end

	-- Update tracking
	self.monitor_current_ws[monitor_name] = current_ws
	self.workspace_usage[current_ws] = (self.workspace_usage[current_ws] or 0) + 1

	Logger.info(
		string.format(
			"Assigned workspace %d on monitor %s (usage: %d)",
			current_ws,
			monitor_name,
			self.workspace_usage[current_ws]
		)
	)

	return current_ws
end

-- Get current usage count for a workspace
function WorkspaceAllocator:get_usage(workspace)
	return self.workspace_usage[workspace] or 0
end

-- Get current workspace for a monitor
function WorkspaceAllocator:get_current_for_monitor(monitor_name)
	return self.monitor_current_ws[monitor_name]
end

return WorkspaceAllocator
