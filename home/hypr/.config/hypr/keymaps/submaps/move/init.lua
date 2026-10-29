--- Move submap
--- Each bind moves the selected windows (lib/selection.lua), or the focused one when none is selected

local Config = require("config") ---@class Config
local Direction = require("lib.key.direction") ---@class Direction
local Submap = require("lib.key.submap") ---@class Submap

-- The actions the rows name.
require("lib.act.defs.launch")
require("lib.act.defs.move")
require("lib.act.defs.windows_select")

local function enter_submap(name) return { "submap.enter", { name } } end

--- The four directions as actions that nudge by `amount` pixels.
--- @param amount number
--- @return DirActions
local function nudge(amount)
  return {
    left = { "move.step", { "left", amount } },
    down = { "move.step", { "down", amount } },
    up = { "move.step", { "up", amount } },
    right = { "move.step", { "right", amount } },
  }
end

Submap.define({
  name = "Move",
  desc = "+Move",
  enter = Config.leader .. " + SHIFT + M",

  escape = "reset",
  catchall = "stay",
  targets = true,

  hint = {
    { "Move", { "move.step", tiers = "speed" } },
    { "Window", { "windows.float_selected", label = "Float" } },
    { "Mode", "submap.enter" },
  },

  binds = function()
    -- Straight to the other `targets` submaps, so the selection carries; BackSpace only goes back one step.
    local keys = {
      { "F", "windows.float_selected", "Toggle Floating" },
      { "W", enter_submap("Windows"), "+Windows" },
      { "R", enter_submap("Resize"), "+Resize" },
    }

    for _, key in ipairs(Direction.speed_binds(nudge, "Move")) do
      keys[#keys + 1] = key
    end

    return keys
  end,
}).setup()
