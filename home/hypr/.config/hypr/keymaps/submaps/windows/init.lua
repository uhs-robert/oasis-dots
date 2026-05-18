--- Windows submap

local Config = require("config") ---@class Config
local Direction = require("lib.key.direction") ---@class Direction
local Submap = require("lib.key.submap") ---@class Submap
local Apps = require("lib.actions.apps") ---@class Apps
local Window = require("lib.actions.window") ---@class WindowActions
local Workspace = require("lib.actions.workspace") ---@class WorkspaceActions

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

return Submap.define({
  name = "Windows",
  desc = "+Windows",
  enter = Config.leader .. " + W",

  escape = "reset",
  catchall = "stay",

  binds = function()
    -- Focus (no mod)
    local focus_actions = {
      left = Window.focus_dir("l"),
      down = Window.focus_dir("d"),
      up = Window.focus_dir("u"),
      right = Window.focus_dir("r"),
    }

    -- Move window (SHIFT)
    local move_actions = {
      left = Window.move_dir("l"),
      down = Window.move_dir("d"),
      up = Window.move_dir("u"),
      right = Window.move_dir("r"),
    }

    -- Workspace navigation (CTRL)
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

    local rows = {}

    -- Directional tiers
    for _, row in ipairs(Direction.binds(focus_actions, "Focus")) do
      table.insert(rows, row)
    end
    for _, row in ipairs(Direction.binds(move_actions, "Move", "SHIFT")) do
      table.insert(rows, row)
    end
    for _, row in ipairs(Direction.binds(ws_actions, "Workspace", "CTRL")) do
      table.insert(rows, row)
    end

    -- Submap switches
    table.insert(rows, { "R", function() Submap.enter("Resize") end, "+Resize" })
    table.insert(rows, { "M", function() Submap.enter("Move") end, "+Move" })
    table.insert(rows, { "I", function() Submap.enter("Screenshot") end, "+Screenshot" })
    table.insert(rows, { "Q", function() Submap.enter("System") end, "+System" })
    table.insert(rows, { "X", function() Submap.enter("Cursor") end, "+Cursor" })

    -- Other binds
    -- stylua: ignore start
    table.insert(rows, { "TAB",           Workspace.focus_last(),   "Last Workspace" })
    table.insert(rows, { "O",             exec(Apps.open(MENU .. " -i -show window")),  "Search Windows" })
    table.insert(rows, { "C",             Window.kill(),             "Close Window" })
    table.insert(rows, { "F",             Window.float_toggle(),           "Toggle Floating" })
    table.insert(rows, { "P",             Window.pseudo_toggle(),          "Toggle Pseudo" })
    table.insert(rows, { "S",             Window.layout_toggle(),          "Toggle Split" })
    table.insert(rows, { "MINUS",         Window.layout_toggle(),          "Toggle Split" })
    table.insert(rows, { "RETURN",        Window.pass_to_active(),         "Confirm Selection" })
    table.insert(rows, { "SHIFT + SLASH", function() require("hyprvim.whichkey").toggle() end, "WhichKey" })
    -- stylua: ignore end

    -- Move window to workspace (SHIFT + number)
    for i = 1, Config.persistent_workspaces or 10 do
      local key = tostring(i % 10)
      local action = Config.persistent_workspaces and Workspace.move_local(i) or Workspace.move(i)
      table.insert(rows, { "SHIFT + " .. key, action, "Move to WS " .. i })
    end

    -- Monitor focus (number keys)
    for i = 1, math.max(#Config.monitors, 10) do
      table.insert(rows, { tostring(i % 10), Window.focus_monitor(i), "Monitor " .. i })
    end

    return rows
  end,
})
