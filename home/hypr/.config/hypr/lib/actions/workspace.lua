--- Workspace navigation actions: focus, move window, cycle, scroll.

local Workspaces = require("lib.workspaces") ---@class Workspaces
local Hypr = require("lib.hypr") ---@class HyprLib

--- @param ws HL.WorkspaceSelector
local focus = function(ws) return Hypr.dispatch(hl.dsp.focus({ workspace = ws })) end

--- @param ws HL.WorkspaceSelector
local move_win = function(ws) return Hypr.dispatch(hl.dsp.window.move({ workspace = ws })) end

--- @class WorkspaceActions
local Workspace = {
  focus_last = function() return focus("previous") end,
  cycle_next = function() return focus("e+1") end,
  cycle_prev = function() return focus("e-1") end,
  move_next = function() return move_win("e+1") end,
  move_prev = function() return move_win("e-1") end,
}

--- Focus workspace by index.
--- @param n integer
Workspace.focus = function(n) return focus(n) end

--- Move active window to workspace by index.
--- @param n integer
Workspace.move = function(n) return move_win(n) end

-- "r" selectors below are per-monitor workspace selectors, including empty
-- See: https://wiki.hypr.land/Configuring/Basics/Dispatchers/#workspace-selectors

--- Focus the monitor-local workspace at slot (persistent workspace mode).
--- @param slot integer
Workspace.focus_local = function(slot) return focus("r~" .. slot) end

--- Move active window to the monitor-local workspace at slot.
--- @param slot integer
Workspace.move_local = function(slot) return move_win("r~" .. slot) end

--- Cycle to the previous or next workspace on the active monitor.
--- @param dir "prev"|"next"
--- @return fun()
Workspace.cycle_local = function(dir) return focus(dir == "next" and "r+1" or "r-1") end

--- Move the active window to the previous or next workspace on the active monitor.
--- @param dir "prev"|"next"
--- @return fun()
Workspace.move_window_local = function(dir) return move_win(dir == "next" and "r+1" or "r-1") end

return Workspace
