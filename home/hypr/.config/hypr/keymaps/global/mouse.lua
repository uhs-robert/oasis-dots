local Bind = require("lib.key.bind")
local Window = require("lib.actions.window")
local Workspace = require("lib.actions.workspace")

-- stylua: ignore start

-- Mouse Keys
Bind.leader_key("mouse_down", Workspace.scroll_next())
Bind.leader_key("mouse_up",   Workspace.scroll_prev())
Bind.leader_key("mouse:272",  Window.drag())
Bind.leader_key("mouse:273",  Window.resize_mouse())
