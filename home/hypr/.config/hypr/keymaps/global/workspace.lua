local Bind = require("lib.key.bind") ---@class BindLib
local Config = require("config") ---@class Config
local Workspace = require("lib.actions.workspace") ---@class WorkspaceActions

local OPTS = {
  repeating = function(description) return { desc = description, repeating = true } end,
  universal = function(description) return { desc = description, submap_universal = true } end,
}
-- stylua: ignore start

--- Bind monitor-local workspace keys using `Config.persistent_workspaces` slot count.
local bind_local_ws = function()
  for i = 1, Config.persistent_workspaces do
    local key = i % 10
    Bind.leader_key("" .. key,         Workspace.focus_local(i), OPTS.universal("Go to Workspace " .. i))
    Bind.leader_key("SHIFT + " .. key, Workspace.move_local(i),  "Move to Workspace " .. i)
  end

  Bind.leader_key({ "CTRL + H", "CTRL + LEFT" },  Workspace.cycle_local("prev"),        OPTS.repeating("Prev WS on Monitor"))
  Bind.leader_key({ "CTRL + L", "CTRL + RIGHT" }, Workspace.cycle_local("next"),        OPTS.repeating("Next WS on Monitor"))
  Bind.leader_key({ "CTRL + J", "CTRL + DOWN" },  Workspace.move_window_local("prev"),  "Move window to prev WS")
  Bind.leader_key({ "CTRL + K", "CTRL + UP" },    Workspace.move_window_local("next"),  "Move window to next WS")
end

--- Bind global workspaces 1–10 with cycle and move keys.
local bind_global_ws = function()
  for i = 1, 10 do
    local key = i % 10
    Bind.leader_key("" .. key,         Workspace.focus(i), OPTS.universal("Go to Workspace " .. i))
    Bind.leader_key("SHIFT + " .. key, Workspace.move(i),  "Move to Workspace " .. i)
  end

  Bind.leader_key({ "CTRL + H", "CTRL + LEFT" },  Workspace.cycle_prev(), OPTS.repeating("Prev WS"))
  Bind.leader_key({ "CTRL + L", "CTRL + RIGHT" }, Workspace.cycle_next(), OPTS.repeating("Next WS"))
  Bind.leader_key({ "CTRL + J", "CTRL + DOWN" },  Workspace.move_prev(),  "Move window to prev WS")
  Bind.leader_key({ "CTRL + K", "CTRL + UP" },    Workspace.move_next(),  "Move window to next WS")
end

if Config.persistent_workspaces then bind_local_ws() else bind_global_ws() end
