-- hypr/.config/hypr/lua/config/monitors.lua
-- Monitor configuration for app launching

local MonitorConfig = {}

-- Monitor names mapped to workspace groups
-- Format: MONITOR_NAME = workspace_group_id
-- Valid monitor names for use in app-setups.lua:
--   PRIMARY, LEFT, RIGHT, CENTER

MonitorConfig.MONITOR_MAP = {
	PRIMARY = 0, -- Workspace group 0 → Workspaces 1-5 (could also be the built-in laptop display)
	LEFT = 1, -- Workspace group 1 → Workspaces 6-10
	RIGHT = 2, -- Workspace group 2 → Workspaces 11-15
	CENTER = 3, -- Workspace group 3 → Workspaces 16-20
}

-- To add more monitors:
-- MonitorConfig.MONITOR_MAP.TOP = 4     -- Workspace group 4 → Workspaces 21-25
-- MonitorConfig.MONITOR_MAP.BOTTOM = 5  -- Workspace group 5 → Workspaces 26-30

return MonitorConfig
