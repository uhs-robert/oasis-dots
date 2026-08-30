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

--- Focus the previously focused window.
Window.focus_last = function() return Hypr.dispatch(hl.dsp.focus({ last = true })) end

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

--- Cycle focus through floating windows on the active workspace.
--- @param dir "next"|"prev"
--- @return fun()
Window.cycle_float = function(dir)
  return function()
    local ws = hl.get_active_workspace()
    if not ws then return end
    local active = hl.get_active_window()
    local floats = {}
    for _, w in ipairs(hl.get_windows() or {}) do
      if w.floating and w.workspace and w.workspace.id == ws.id then floats[#floats + 1] = w end
    end
    if #floats == 0 then return end
    local idx = 0
    if active then
      for i, w in ipairs(floats) do
        if w.address == active.address then
          idx = i
          break
        end
      end
    end
    local next_idx = dir == "prev" and ((idx - 2) % #floats + 1) or (idx % #floats + 1)
    hl.dispatch(hl.dsp.focus({ window = "address:" .. floats[next_idx].address }))
  end
end

return Window
