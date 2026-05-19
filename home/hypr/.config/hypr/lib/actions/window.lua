--- Window management actions: focus direction, move direction, close, fullscreen, scratchpad, monitors.

local Workspaces = require("lib.workspaces") --- @class Workspaces
local Hypr = require("lib.hypr") --- @class HyprLib

--- @class WindowActions
local Window = {
  close = function() return Hypr.dispatch(hl.dsp.window.close()) end,
  kill = function() return Hypr.dispatch(hl.dsp.window.kill()) end,
  fullscreen_toggle = function() return Hypr.dispatch(hl.dsp.window.fullscreen({ action = "toggle" })) end,
  float_toggle = function() return Hypr.dispatch(hl.dsp.window.float({ action = "toggle" })) end,
  pseudo_toggle = function() return Hypr.dispatch(hl.dsp.window.pseudo()) end,
  layout_toggle = function() return Hypr.dispatch(hl.dsp.layout("togglesplit")) end,
  pass_to_active = function() return Hypr.dispatch(hl.dsp.pass({ window = "active" })) end,
  drag = function() return Hypr.dispatch(hl.dsp.window.drag()) end,
  resize_mouse = function() return Hypr.dispatch(hl.dsp.window.resize()) end,
}

local SPECIAL_WS = {
  scratchpad = "special:scratchpad",
}

--- Focus the monitor in the given slot (1-based index into Config.monitors).
--- @param slot integer
Window.focus_monitor = function(slot)
  return function()
    local sel = Workspaces.get_monitor_for_slot(slot)
    if sel then hl.dispatch(hl.dsp.focus({ monitor = sel })) end
  end
end

--- @param dir string  Direction code: "l", "d", "u", "r"
Window.focus_dir = function(dir) return Hypr.dispatch(hl.dsp.focus({ direction = dir })) end

--- @param dir string  Direction code: "l", "d", "u", "r"
Window.move_dir = function(dir) return Hypr.dispatch(hl.dsp.window.move({ direction = dir })) end

--- @param name string  Key into SPECIAL_WS (e.g. "scratchpad")
Window.toggle_special = function(name) return Hypr.dispatch(hl.dsp.workspace.toggle_special(name)) end

--- @param name string  Key into SPECIAL_WS (e.g. "scratchpad")
Window.move_to_special = function(name) return Hypr.dispatch(hl.dsp.window.move({ workspace = SPECIAL_WS[name] })) end

--- Move the active window to the monitor in the given slot.
--- @param slot integer
Window.move_to_monitor = function(slot)
  return function()
    local sel = Workspaces.get_monitor_for_slot(slot)
    if sel then hl.dispatch(hl.dsp.window.move({ monitor = sel, follow = true })) end
  end
end

--- Focus a window matching arbitrary hl.dsp.focus opts (e.g. { window = "title:..." }).
--- @param opts table
Window.focus_by = function(opts) return Hypr.dispatch(hl.dsp.focus(opts)) end

return Window
