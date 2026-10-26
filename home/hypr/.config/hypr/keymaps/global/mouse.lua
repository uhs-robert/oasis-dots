local Act = require("lib.act") ---@class ActionLib
local Bind = require("lib.key.bind") ---@class BindLib
local Window = require("lib.actions.window") ---@class WindowActions

-- The wheel cycles workspaces. Drag and resize stay binds: they need the mouse dispatchers, which an action
-- performed from a script cannot start.
Act.bind("workspace.cycle", { key = { key = "mouse_down", leader = true }, args = { "next" }, desc = false })
Act.bind("workspace.cycle", { key = { key = "mouse_up", leader = true }, args = { "prev" }, desc = false })
Bind.leader_key("mouse:272", Window.drag())
Bind.leader_key("mouse:273", Window.resize_mouse())
