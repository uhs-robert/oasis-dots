local Bind = require("lib.key.bind") ---@class BindLib
local Window = require("lib.actions.window") ---@class WindowActions
local Workspace = require("lib.actions.workspace") ---@class WorkspaceActions
local Config = require("config") ---@class Config

local PERSISTENT_WS = Config.persistent_workspaces

-- Mouse Keys
-- stylua: ignore start
Bind.leader_key("mouse_down", PERSISTENT_WS and Workspace.cycle_local("next") or Workspace.cycle_next())
Bind.leader_key("mouse_up",   PERSISTENT_WS and Workspace.cycle_local("prev") or Workspace.cycle_prev())
Bind.leader_key("mouse:272",  Window.drag())
Bind.leader_key("mouse:273",  Window.resize_mouse())
