--- Workspace navigation actions: focus, move window, cycle, scroll.

local Workspaces = require("lib.workspaces")

--- @class WorkspaceActions
local Workspace = {}

--- Focus workspace by index.
--- @param n integer
--- @return fun()
function Workspace.focus(n)
  return function() hl.dispatch(hl.dsp.focus({ workspace = n })) end
end

--- Move active window to workspace by index.
--- @param n integer
--- @return fun()
function Workspace.move(n)
  return function() hl.dispatch(hl.dsp.window.move({ workspace = n })) end
end

--- @return fun()
function Workspace.focus_last()
  return function() hl.dispatch(hl.dsp.focus({ workspace = "previous" })) end
end

--- @return fun()
function Workspace.cycle_next()
  return function() hl.dispatch(hl.dsp.focus({ workspace = "e+1" })) end
end

--- @return fun()
function Workspace.cycle_prev()
  return function() hl.dispatch(hl.dsp.focus({ workspace = "e-1" })) end
end

--- @return fun()
function Workspace.move_next()
  return function() hl.dispatch(hl.dsp.window.move({ workspace = "e+1" })) end
end

--- @return fun()
function Workspace.move_prev()
  return function() hl.dispatch(hl.dsp.window.move({ workspace = "e-1" })) end
end

--- Focus the monitor-local workspace at slot (persistent workspace mode).
--- @param slot integer
--- @return fun()
function Workspace.focus_local(slot)
  return function() hl.dispatch(hl.dsp.focus({ workspace = Workspaces.get_ws_id(slot) })) end
end

--- Move active window to the monitor-local workspace at slot.
--- @param slot integer
--- @return fun()
function Workspace.move_local(slot)
  return function() hl.dispatch(hl.dsp.window.move({ workspace = Workspaces.get_ws_id(slot) })) end
end

--- @param dir "prev"|"next"
--- @return fun()
function Workspace.cycle_local(dir)
  return function() Workspaces.cycle_local_ws(dir) end
end

--- @param dir "prev"|"next"
--- @return fun()
function Workspace.move_window_local(dir)
  return function() Workspaces.move_window_local_ws(dir) end
end

--- Scroll workspaces (for mouse wheel binds).
--- @return fun()
function Workspace.scroll_next()
  return function() hl.dispatch(hl.dsp.focus({ workspace = "e+1" })) end
end

--- @return fun()
function Workspace.scroll_prev()
  return function() hl.dispatch(hl.dsp.focus({ workspace = "e-1" })) end
end

return Workspace
