--- Windows submap

local Config = require("config") ---@class Config
local Direction = require("lib.key.direction") ---@class Direction
local Submap = require("lib.key.submap") ---@class Submap
local Apps = require("lib.actions.apps") ---@class Apps
local Window = require("lib.actions.window") ---@class WindowActions
local Workspace = require("lib.actions.workspace") ---@class WorkspaceActions
local Lazy = require("lib.lazy") ---@type Lazy

local MENU = Config.app.menu

--- Wrap an action to exit the submap before firing.
--- @param fn fun()
--- @return fun()
local function exec(fn)
  return function()
    Submap.reset()
    fn()
  end
end

Submap.define({
  name = "Windows",
  desc = "+Windows",
  enter = Config.leader .. " + W",

  escape = "reset",
  catchall = "stay",

  binds = function()
    local focus_actions = {
      left = Window.focus_dir("l"),
      down = Window.focus_dir("d"),
      up = Window.focus_dir("u"),
      right = Window.focus_dir("r"),
    }

    local move_actions = {
      left = Window.move_dir("l"),
      down = Window.move_dir("d"),
      up = Window.move_dir("u"),
      right = Window.move_dir("r"),
    }

    local ws_actions
    if Config.persistent_workspaces then
      ws_actions = {
        left = Workspace.cycle_local("prev"),
        down = Workspace.move_window_local("prev"),
        up = Workspace.move_window_local("next"),
        right = Workspace.cycle_local("next"),
      }
    else
      ws_actions = {
        left = Workspace.cycle_prev(),
        down = Workspace.move_prev(),
        up = Workspace.move_next(),
        right = Workspace.cycle_next(),
      }
    end

    -- stylua: ignore start
    local keys = {
      { "R",             Submap.switch("Resize"),       "+Resize" },
      { "M",             Submap.switch("Move"),         "+Move" },
      { "I",             Submap.switch("Screenshot"),   "+Screenshot" },
      { "Q",             Submap.switch("System"),       "+System" },
      { "X",             Submap.switch("Cursor"),       "+Cursor" },
      { "TAB",           Workspace.focus_last(),                      "Last Workspace" },
      { "O",             exec(Apps.open(MENU .. " -i -show window")), "Search Windows" },
      { "C",             Window.kill(),                               "Close Window" },
      { "F",             Window.float_toggle(),                       "Toggle Floating" },
      { "P",             Window.pseudo_toggle(),                      "Toggle Pseudo" },
      { "S",             Window.layout_toggle(),                      "Toggle Split" },
      { "MINUS",         Window.layout_toggle(),                      "Toggle Split" },
      { "RETURN",        Window.pass_to_active(),                     "Confirm Selection" },
      { "SHIFT + SLASH", Lazy.load("hyprvim.whichkey").toggle,        "WhichKey" },
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
      keys[#keys + 1] = { "SHIFT + " .. k, action, "Move to WS " .. i }
    end

    for i = 1, math.max(#Config.monitors, 10) do
      keys[#keys + 1] = { tostring(i % 10), Window.focus_monitor(i), "Monitor " .. i }
    end

    return keys
  end,
}).setup()
