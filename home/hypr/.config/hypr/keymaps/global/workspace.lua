local Bind = require("lib.key.bind") ---@class BindLib
local Config = require("config") ---@class Config
local Workspace = require("lib.actions.workspace") ---@class WorkspaceActions
-- stylua: ignore start

--- Bind monitor-local workspace keys using `Config.persistent_workspaces` slot count.
local bind_local_ws = function()
  for i = 1, Config.persistent_workspaces do
    local key = i % 10
    Bind.leader_key("" .. key,         Workspace.focus_local(i), { submap_universal = true, desc = "Go to Workspace " .. i })
    Bind.leader_key("SHIFT + " .. key, Workspace.move_local(i),  { desc = "Move to Workspace " .. i })
  end

  Bind.leader_key({ "CTRL + H", "CTRL + LEFT" },  Workspace.cycle_local("prev"),        "Prev WS on Monitor",      { repeating = true })
  Bind.leader_key({ "CTRL + L", "CTRL + RIGHT" }, Workspace.cycle_local("next"),        "Next WS on Monitor",      { repeating = true })
  Bind.leader_key({ "CTRL + J", "CTRL + DOWN" },  Workspace.move_window_local("prev"),  "Move window to prev WS")
  Bind.leader_key({ "CTRL + K", "CTRL + UP" },    Workspace.move_window_local("next"),  "Move window to next WS")
end

--- Bind global workspaces 1–10 with cycle and move keys.
local bind_global_ws = function()
  for i = 1, 10 do
    local key = i % 10
    Bind.leader_key("" .. key,         Workspace.focus(i), { submap_universal = true, desc = "Go to Workspace " .. i })
    Bind.leader_key("SHIFT + " .. key, Workspace.move(i),  { desc = "Move to Workspace " .. i })
  end

  Bind.leader_key({ "CTRL + H", "CTRL + LEFT" },  Workspace.cycle_prev(), "Prev WS",                { repeating = true })
  Bind.leader_key({ "CTRL + L", "CTRL + RIGHT" }, Workspace.cycle_next(), "Next WS",                { repeating = true })
  Bind.leader_key({ "CTRL + J", "CTRL + DOWN" },  Workspace.move_prev(),  "Move window to prev WS")
  Bind.leader_key({ "CTRL + K", "CTRL + UP" },    Workspace.move_next(),  "Move window to next WS")
end

if Config.persistent_workspaces then bind_local_ws() else bind_global_ws() end
