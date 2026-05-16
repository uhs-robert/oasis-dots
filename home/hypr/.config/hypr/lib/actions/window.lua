--- Window management actions: focus direction, move direction, close, fullscreen, scratchpad, monitors.

local Config = require("config")
local Workspaces = require("lib.workspaces")

--- @class WindowActions
local Window = {}

local SCRATCHPAD_NAME = "scratchpad"
local SCRATCHPAD_WS   = "special:scratchpad"

--- @return fun()
function Window.close()
  return function() hl.dispatch(hl.dsp.window.close()) end
end

--- @return fun()
function Window.fullscreen_toggle()
  return function() hl.dispatch(hl.dsp.window.fullscreen({ action = "toggle" })) end
end

--- @param dir string  Direction code: "l", "r", "u", "d"
--- @return fun()
function Window.focus_dir(dir)
  return function() hl.dispatch(hl.dsp.focus({ direction = dir })) end
end

--- @param dir string  Direction code: "l", "r", "u", "d"
--- @return fun()
function Window.move_dir(dir)
  return function() hl.dispatch(hl.dsp.window.move({ direction = dir })) end
end

--- @return fun()
function Window.toggle_scratchpad()
  return function() hl.dispatch(hl.dsp.workspace.toggle_special(SCRATCHPAD_NAME)) end
end

--- @return fun()
function Window.move_to_scratchpad()
  return function() hl.dispatch(hl.dsp.window.move({ workspace = SCRATCHPAD_WS })) end
end

--- Focus the monitor in the given slot (1-based index into Config.monitors).
--- @param slot integer
--- @return fun()
function Window.focus_monitor(slot)
  return function()
    local sel = Workspaces.get_monitor_for_slot(slot)
    if sel then hl.dispatch(hl.dsp.focus({ monitor = sel })) end
  end
end

--- Move the active window to the monitor in the given slot.
--- @param slot integer
--- @return fun()
function Window.move_to_monitor(slot)
  return function()
    local sel = Workspaces.get_monitor_for_slot(slot)
    if sel then hl.dispatch(hl.dsp.window.move({ monitor = sel, follow = true })) end
  end
end

--- Forcefully kill the active window (no graceful close).
--- @return fun()
function Window.kill()
  return function() hl.dispatch(hl.dsp.window.kill()) end
end

--- @return fun()
function Window.float_toggle()
  return function() hl.dispatch(hl.dsp.window.float({ action = "toggle" })) end
end

--- @return fun()
function Window.pseudo_toggle()
  return function() hl.dispatch(hl.dsp.window.pseudo()) end
end

--- @return fun()
function Window.layout_toggle()
  return function() hl.dispatch(hl.dsp.layout("togglesplit")) end
end

--- Focus a window matching arbitrary hl.dsp.focus opts (e.g. { window = "title:..." }).
--- @param opts table
--- @return fun()
function Window.focus_by(opts)
  return function() hl.dispatch(hl.dsp.focus(opts)) end
end

--- Pass the active key event through to the active window.
--- @return fun()
function Window.pass_to_active()
  return function() hl.dispatch(hl.dsp.exec_cmd("hyprctl dispatch pass activewindow")) end
end

--- @return fun()
function Window.drag()
  return function() hl.dispatch(hl.dsp.window.drag()) end
end

--- @return fun()
function Window.resize_mouse()
  return function() hl.dispatch(hl.dsp.window.resize()) end
end

return Window
