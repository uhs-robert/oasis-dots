--- Workspace navigation actions: focus, move window, cycle, scroll.

local Workspaces = require("lib.workspaces") ---@class Workspaces
local Hypr = require("lib.hypr") ---@class HyprLib

--- @class WorkspaceActions
local Workspace = {}

--- @param ws HL.WorkspaceSelector
local focus = function(ws) return Hypr.dispatch(hl.dsp.focus({ workspace = ws })) end

--- @param ws HL.WorkspaceSelector
local move_win = function(ws) return Hypr.dispatch(hl.dsp.window.move({ workspace = ws })) end

-- Basic Actions
function Workspace.focus_last() return focus("previous") end
function Workspace.cycle_next() return focus("e+1") end
function Workspace.cycle_prev() return focus("e-1") end
function Workspace.move_next() return move_win("e+1") end
function Workspace.move_prev() return move_win("e-1") end

--- Focus workspace by index.
--- @param n integer
function Workspace.focus(n) return focus(n) end

--- Move active window to workspace by index.
--- @param n integer
function Workspace.move(n) return move_win(n) end

--- Focus the monitor-local workspace at slot (persistent workspace mode).
--- @param slot integer
function Workspace.focus_local(slot) return focus(Workspaces.get_ws_id(slot)) end

--- Move active window to the monitor-local workspace at slot.
--- @param slot integer
function Workspace.move_local(slot) return move_win(Workspaces.get_ws_id(slot)) end

--- Cycle to the previous or next workspace on the active monitor, wrapping at the boundary.
--- @param dir "prev"|"next"
--- @return fun()
function Workspace.cycle_local(dir)
  return function() Workspaces.cycle_local_ws(dir) end
end

--- Move the active window to the previous or next workspace on the active monitor, wrapping at the boundary.
--- @param dir "prev"|"next"
--- @return fun()
function Workspace.move_window_local(dir)
  return function() Workspaces.move_window_local_ws(dir) end
end

return Workspace
