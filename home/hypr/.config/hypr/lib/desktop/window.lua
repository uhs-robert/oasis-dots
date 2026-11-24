--- Window management: focus direction, move direction, close, fullscreen, special workspaces, monitors.

local Config = require("config") --- @class Config
local Workspaces = require("lib.workspaces") --- @class Workspaces
local Hypr = require("lib.hypr") --- @class HyprLib
local Closed = require("lib.closed_windows") --- @class ClosedWindows

--- Close the active window so it can be restored afterwards.
--- @param action "close"|"kill"
--- @return fun()
local function close_active(action)
  return function() Closed.close({ hl.get_active_window() }, action) end
end

--- @class WindowActions
local Window = {
  close = function() return close_active("close") end,
  kill = function() return close_active("kill") end,
  restore_closed = function() return Closed.restore end,
  fullscreen_toggle = function() return Hypr.dispatch(hl.dsp.window.fullscreen({ action = "toggle" })) end,
  -- Mode 1 keeps the frame and bar; the flush edges come from the workspace rules in config/general/frame.lua. A lone
  -- window is already flush inside the frame, so there the key toggles that flush instead.
  maximize_toggle = function()
    return function()
      if _G.ScreenFrame and _G.ScreenFrame.toggle_lone_flush() then return end
      hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }))
    end
  end,
  float_toggle = function() return Hypr.dispatch(hl.dsp.window.float({ action = "toggle" })) end,
  pseudo_toggle = function() return Hypr.dispatch(hl.dsp.window.pseudo()) end,
  layout_toggle = function() return Hypr.dispatch(hl.dsp.layout("togglesplit")) end,
  pass_to_active = function() return Hypr.dispatch(hl.dsp.pass({ window = "active" })) end,
  drag = function() return Hypr.dispatch(hl.dsp.window.drag()) end,
  resize_mouse = function() return Hypr.dispatch(hl.dsp.window.resize()) end,
  group_toggle = function() return Hypr.dispatch(hl.dsp.group.toggle()) end,
  group_next = function() return Hypr.dispatch(hl.dsp.group.next()) end,
  group_prev = function() return Hypr.dispatch(hl.dsp.group.prev()) end,
  group_move_out = function() return Hypr.dispatch(hl.dsp.window.move({ out_of_group = true })) end,
  group_lock_toggle = function() return Hypr.dispatch(hl.dsp.group.lock_active({ action = "toggle" })) end,
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

--- Focus the urgent window, or the previously focused window if none is urgent.
Window.focus_urgent_or_last = function() return Hypr.dispatch(hl.dsp.focus({ urgent_or_last = true })) end

--- @param dir string  Direction code: "l", "d", "u", "r"
Window.focus_dir = function(dir) return Hypr.dispatch(hl.dsp.focus({ direction = dir })) end

--- @param dir string  Direction code: "l", "d", "u", "r"
Window.move_dir = function(dir) return Hypr.dispatch(hl.dsp.window.move({ direction = dir })) end

--- Move the active window into the group in the given direction if group.
--- @param dir string  Direction code: "l", "d", "u", "r"
Window.group_move_in = function(dir) return Hypr.dispatch(hl.dsp.window.move({ into_group = dir })) end

--- Move the active window into the group in the given direction or create.
--- @param dir string  Direction code: "l", "d", "u", "r"
Window.group_move_or_create = function(dir) return Hypr.dispatch(hl.dsp.window.move({ into_or_create_group = dir })) end

--- @param name string  Special workspace name without the `special:` prefix
--- @return boolean
local function special_has_window(name)
  local ws_name = "special:" .. name
  for _, w in ipairs(hl.get_windows()) do
    if w.workspace and w.workspace.name == ws_name then return true end
  end
  return false
end

--- @type table<string, boolean>
local claimed_classes = {}

--- Send every window of the entry's class to its special workspace, from the first launch until a reload.
--- @param name  string
--- @param class string
local function claim_class(name, class)
  if claimed_classes[name] then return end
  claimed_classes[name] = true
  hl.window_rule({
    name = "special-" .. name,
    -- Hyprland reads match.class as a regex; escape it so a class such as "notes+work" matches literally.
    match = { class = "^" .. class:gsub("[%^%$%(%)%.%[%]%*%+%?{}|\\]", "\\%0") .. "$" },
    workspace = "special:" .. name,
  })
end

-- 10 s: a browser can take a few seconds to load the page and set its title.
local ADOPT_POLL_MS = 250
local ADOPT_ATTEMPTS = 40

--- Show the special workspace on the focused monitor unless it is already up there.
--- @param name string
local function show_special(name)
  local monitor = hl.get_active_monitor()
  local shown = monitor and monitor.active_special_workspace
  if not (shown and shown.name == "special:" .. name) then hl.dispatch(hl.dsp.workspace.toggle_special(name)) end
end

--- Specials with a launch still waiting for its window.
--- @type table<string, boolean>
local adopting = {}

--- Launch the entry's cmd, then move only its new window onto the special: the first window that was not open
--- before, has the entry's class and has its title in the window title. A rule on a shared class (a browser) would
--- also take the user's other windows, such as the ones a browser restores at its start.
--- @param name string
--- @param spec Config.SpecialWorkspace
local function launch_and_adopt(name, spec)
  -- A second press before the window shows starts no second launch: its poller could take the first window again
  -- and leave the second one off the special.
  if adopting[name] then return end
  adopting[name] = true
  local before = {}
  for _, w in ipairs(hl.get_windows()) do
    before[w.address] = true
  end
  hl.dispatch(hl.dsp.exec_cmd(spec.cmd))
  local attempts = 0
  local timer
  timer = hl.timer(function()
    attempts = attempts + 1
    for _, w in ipairs(hl.get_windows() or {}) do
      if not before[w.address] and w.class == spec.class and string.find(w.title, spec.title, 1, true) then
        timer:set_enabled(false)
        adopting[name] = nil
        hl.dispatch(
          hl.dsp.window.move({ window = "address:" .. w.address, workspace = "special:" .. name, follow = false })
        )
        show_special(name)
        return
      end
    end
    if attempts >= ADOPT_ATTEMPTS then
      timer:set_enabled(false)
      adopting[name] = nil
    end
  end, { timeout = ADOPT_POLL_MS, type = "repeat" })
end

--- Show or hide a special workspace. One declared in Config.special_workspaces with a `cmd` launches it when empty.
--- @param name string  Special workspace name without the `special:` prefix (e.g. "scratchpad")
Window.toggle_special = function(name)
  return function()
    local spec = Config.special_workspaces[name]
    if spec and spec.cmd and not special_has_window(name) then
      -- A non-silent workspace rule opens the special as the window lands, so no toggle is needed. The exec rule
      -- follows the launched PID, which misses a window that a running process opens (kitty --single-instance);
      -- a class rule catches those.
      if spec.class and spec.title then
        launch_and_adopt(name, spec)
      elseif spec.class then
        claim_class(name, spec.class)
        hl.dispatch(hl.dsp.exec_cmd(spec.cmd))
      else
        hl.dispatch(hl.dsp.exec_cmd(spec.cmd, { workspace = "special:" .. name }))
      end
      return
    end
    hl.dispatch(hl.dsp.workspace.toggle_special(name))
  end
end

--- @param name string  Special workspace name without the `special:` prefix (e.g. "scratchpad")
Window.move_to_special = function(name) return Hypr.dispatch(hl.dsp.window.move({ workspace = "special:" .. name })) end

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

_G._hv_cycle_float = function(dir) Window.cycle_float(dir)() end

--- Focus a notification toast, else an open bar popup, else cycle floats.
--- @param dir "next"|"prev"
--- @return fun()
Window.focus_toast_popup_or_float = function(dir)
  return Hypr.exec(require("lib.scripts").focus_toast_popup_or_float .. " " .. dir)
end

return Window
