--- Window management actions: focus direction, move direction, close, fullscreen, scratchpad, monitors.

local Workspaces = require("lib.workspaces") --- @class Workspaces
local Hypr = require("lib.hypr") --- @class HyprLib

--- @class WindowActions
local Window = {}

local SPECIAL_WS = {
  scratchpad = "special:scratchpad",
}

function Window.close() return Hypr.dispatch(hl.dsp.window.close()) end
function Window.kill() return Hypr.dispatch(hl.dsp.window.kill()) end
function Window.fullscreen_toggle() return Hypr.dispatch(hl.dsp.window.fullscreen({ action = "toggle" })) end
function Window.float_toggle() return Hypr.dispatch(hl.dsp.window.float({ action = "toggle" })) end
function Window.pseudo_toggle() return Hypr.dispatch(hl.dsp.window.pseudo()) end
function Window.layout_toggle() return Hypr.dispatch(hl.dsp.layout("togglesplit")) end
function Window.pass_to_active() return Hypr.dispatch(hl.dsp.pass({ window = "active" })) end
function Window.drag() return Hypr.dispatch(hl.dsp.window.drag()) end
function Window.resize_mouse() return Hypr.dispatch(hl.dsp.window.resize()) end

--- Focus the monitor in the given slot (1-based index into Config.monitors).
--- @param slot integer
function Window.focus_monitor(slot)
  return function()
    local sel = Workspaces.get_monitor_for_slot(slot)
    if sel then hl.dispatch(hl.dsp.focus({ monitor = sel })) end
  end
end

--- @param dir string  Direction code: "l", "d", "u", "r"
function Window.focus_dir(dir) return Hypr.dispatch(hl.dsp.focus({ direction = dir })) end

--- @param dir string  Direction code: "l", "d", "u", "r"
function Window.move_dir(dir) return Hypr.dispatch(hl.dsp.window.move({ direction = dir })) end

--- @param name string  Key into SPECIAL_WS (e.g. "scratchpad")
function Window.toggle_special(name) return Hypr.dispatch(hl.dsp.workspace.toggle_special(name)) end

--- @param name string  Key into SPECIAL_WS (e.g. "scratchpad")
function Window.move_to_special(name) return Hypr.dispatch(hl.dsp.window.move({ workspace = SPECIAL_WS[name] })) end

--- Move the active window to the monitor in the given slot.
--- @param slot integer
function Window.move_to_monitor(slot)
  return function()
    local sel = Workspaces.get_monitor_for_slot(slot)
    if sel then hl.dispatch(hl.dsp.window.move({ monitor = sel, follow = true })) end
  end
end

--- Focus a window matching arbitrary hl.dsp.focus opts (e.g. { window = "title:..." }).
--- @param opts table
function Window.focus_by(opts) return Hypr.dispatch(hl.dsp.focus(opts)) end

return Window
