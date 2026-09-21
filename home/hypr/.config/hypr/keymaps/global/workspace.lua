local Bind = require("lib.key.bind") ---@class BindLib
local Config = require("config") ---@class Config
local Direction = require("lib.key.direction") ---@class Direction
local Workspace = require("lib.actions.workspace") ---@class WorkspaceActions

local OPTS = {
  universal = function(description) return { desc = description, submap_universal = true } end,
}
local persistent_ws = Config.persistent_workspaces
local WS_COUNT = type(persistent_ws) == "number" and math.min(persistent_ws, 10) or 10
-- stylua: ignore start

--- Bind CTRL + a letter/arrow pair; only the key shown for Config.vim_mode gets the description.
local ctrl_dir = function(letter, arrow, action, desc, repeating)
  local shown, hidden = Direction.keys(letter, arrow)
  Bind.leader_key("CTRL + " .. shown,  action, { desc = desc, repeating = repeating })
  Bind.leader_key("CTRL + " .. hidden, action, { repeating = repeating })
end

--- Bind monitor-local workspace keys using `Config.persistent_workspaces` slot count.
local bind_local_ws = function()
  for i = 1, WS_COUNT do
    local key = i % 10
    Bind.leader_key("" .. key,         Workspace.focus_local(i), OPTS.universal("Go to Workspace " .. i))
    Bind.leader_key("SHIFT + " .. key, Workspace.move_local(i),  "Move to Workspace " .. i)
  end

  ctrl_dir("H", "LEFT",  Workspace.cycle_local("prev"),       "Prev WS on Monitor", true)
  ctrl_dir("L", "RIGHT", Workspace.cycle_local("next"),       "Next WS on Monitor", true)
  ctrl_dir("J", "DOWN",  Workspace.move_window_local("prev"), "Move window to prev WS")
  ctrl_dir("K", "UP",    Workspace.move_window_local("next"), "Move window to next WS")
end

--- Bind global workspaces with cycle and move keys.
local bind_global_ws = function()
  for i = 1, WS_COUNT do
    local key = i % 10
    Bind.leader_key("" .. key,         Workspace.focus(i), OPTS.universal("Go to Workspace " .. i))
    Bind.leader_key("SHIFT + " .. key, Workspace.move(i),  "Move to Workspace " .. i)
  end

  ctrl_dir("H", "LEFT",  Workspace.cycle_prev(), "Prev WS", true)
  ctrl_dir("L", "RIGHT", Workspace.cycle_next(), "Next WS", true)
  ctrl_dir("J", "DOWN",  Workspace.move_prev(),  "Move window to prev WS")
  ctrl_dir("K", "UP",    Workspace.move_next(),  "Move window to next WS")
end

if Config.persistent_workspaces then bind_local_ws() else bind_global_ws() end
