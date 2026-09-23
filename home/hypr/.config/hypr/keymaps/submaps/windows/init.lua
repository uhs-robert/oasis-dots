--- Windows submap

local Config = require("config") ---@class Config
local Direction = require("lib.key.direction") ---@class Direction
local Submap = require("lib.key.submap") ---@class Submap
local Menu = require("lib.actions.menu") ---@class Menu
local Window = require("lib.actions.window") ---@class WindowActions
local Workspace = require("lib.actions.workspace") ---@class WorkspaceActions

--- Selected windows: { [addr] = { active, inactive } }, stores original border colors
--- Cleared on submap exit.
local SELECTED = {}
local SELECTION_COLOR = "rgba(ffaa00ff)"

--- Return address of the currently focused window, or nil.
local function get_active_address()
  local w = hl.get_active_window()

  return w and w.address or nil
end

--- Return the theme's { active, inactive } border colors.
--- TODO: Convert to Tags/Window Rules when https://github.com/hyprwm/Hyprland/discussions/14030 is resolved.
local function get_theme_borders()
  local ok, Theme = pcall(require, "theme")
  local c = ok and Theme.colors or {}

  return { active = c.theme_primary, inactive = c.bg_mantle }
end

--- Override active + inactive border color for a window by address.
local function set_border(addr, active, inactive)
  hl.dispatch(hl.dsp.window.set_prop({ window = "address:" .. addr, prop = "active_border_color", value = active }))
  hl.dispatch(hl.dsp.window.set_prop({ window = "address:" .. addr, prop = "inactive_border_color", value = inactive }))
end

--- Toggle select on the focused window, highlighting its border.
local function select_toggle()
  local addr = get_active_address()
  if not addr then return end

  if SELECTED[addr] then
    local original = SELECTED[addr]
    SELECTED[addr] = nil
    set_border(addr, original.active, original.inactive)
  else
    SELECTED[addr] = get_theme_borders()
    set_border(addr, SELECTION_COLOR, SELECTION_COLOR)
  end
end

--- Swap the focused window with the one selected window, then clear the selection.
local function swap_selected()
  local active = get_active_address()
  local target, count = nil, 0
  for addr in pairs(SELECTED) do
    if addr ~= active then
      target, count = addr, count + 1
    end
  end
  if not active or count ~= 1 then
    hl.notification.create({ text = "Swap needs exactly one selected window", timeout = 2000 })
    return
  end

  hl.dispatch(hl.dsp.window.swap({ target = "address:" .. target }))
  for addr, original in pairs(SELECTED) do
    set_border(addr, original.active, original.inactive)
    SELECTED[addr] = nil
  end
end

--- Wrap fn so it applies to all selected windows.
--- If no SELECTED, runs fn() on the focused window as normal.
--- Restores focus to the original window after iterating.
--- @param fn fun()
--- @return fun()
local function for_selected(fn)
  return function()
    local any = next(SELECTED)
    if not any then
      fn()
      return
    end

    local original = get_active_address()
    for addr in pairs(SELECTED) do
      hl.dispatch(hl.dsp.focus({ window = "address:" .. addr }))
      fn()
    end
    if original then hl.dispatch(hl.dsp.focus({ window = "address:" .. original })) end
  end
end

Submap.define({
  name = "Windows",
  desc = "+Windows",
  enter = Config.leader .. " + W",

  escape = "reset",
  catchall = "stay",

  on_exit = function()
    for addr, original in pairs(SELECTED) do
      set_border(addr, original.active, original.inactive)
      SELECTED[addr] = nil
    end
  end,

  binds = function()
    local focus_actions = {
      left = Window.focus_dir("l"),
      down = Window.focus_dir("d"),
      up = Window.focus_dir("u"),
      right = Window.focus_dir("r"),
    }

    local move_actions = {
      left = for_selected(Window.move_dir("l")),
      down = for_selected(Window.move_dir("d")),
      up = for_selected(Window.move_dir("u")),
      right = for_selected(Window.move_dir("r")),
    }

    local ws_actions
    if Config.persistent_workspaces then
      ws_actions = {
        left = Workspace.cycle_local("prev"),
        down = for_selected(Workspace.move_window_local("prev")),
        up = for_selected(Workspace.move_window_local("next")),
        right = Workspace.cycle_local("next"),
      }
    else
      ws_actions = {
        left = Workspace.cycle_prev(),
        down = for_selected(Workspace.move_prev()),
        up = for_selected(Workspace.move_next()),
        right = Workspace.cycle_next(),
      }
    end

    local wk_toggle = function() require("lua.plugins.hyprvim").whichkey.toggle() end

    -- stylua: ignore start
    local keys = {
      { "R",             Submap.switch("Resize"),              "+Resize" },
      { "M",             Submap.switch("Move"),                "+Move" },
      { "C",             Submap.switch("Cursor"),              "+Cursor" },
      { "BRACKETLEFT",   Window.cycle_float("prev"),           "Prev Float" },
      { "BRACKETRIGHT",  Window.cycle_float("next"),           "Next Float" },
      { "X",             for_selected(Window.kill()),          "Close Window" },
      { "F",             for_selected(Window.float_toggle()),  "Toggle Floating" },
      { "P",             for_selected(Window.pseudo_toggle()), "Toggle Pseudo" },
      { "MINUS",         for_selected(Window.layout_toggle()), "Toggle Split" },
      { "RETURN",        Window.pass_to_active(),              "Confirm Selection" },
      { "SHIFT + SLASH", wk_toggle,                            "WhichKey" },
      { "SPACE",         select_toggle,                        "Select Window" },
      { "S",             swap_selected,                        "Swap with Selected" },
    }
    -- stylua: ignore end

    for _, key in ipairs(Direction.binds(focus_actions, "Focus")) do
      keys[#keys + 1] = key
    end
    for _, key in ipairs(Direction.binds(move_actions, "Move", "SHIFT")) do
      keys[#keys + 1] = key
    end
    for _, key in ipairs(Direction.binds(ws_actions, "Workspace", "CTRL")) do
      keys[#keys + 1] = key
    end

    for i = 1, Config.persistent_workspaces or 10 do
      local k = tostring(i % 10)
      local action = Config.persistent_workspaces and Workspace.move_local(i) or Workspace.move(i)
      keys[#keys + 1] = { "SHIFT + " .. k, for_selected(action), "Move to WS " .. i }
    end

    for i = 1, math.min(#Config.monitors, 10) do
      keys[#keys + 1] = { tostring(i % 10), Window.focus_monitor(i), "Monitor " .. i }
    end

    return keys
  end,
}).setup()
