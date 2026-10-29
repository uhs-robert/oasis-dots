--- Resize submap
--- Each bind resizes the selected windows (lib/actions/selection.lua), or the focused one when none is selected

local Config = require("config") ---@class Config
local Direction = require("lib.key.direction") ---@class Direction
local Submap = require("lib.key.submap") ---@class Submap

-- The actions the rows name.
require("lib.actions.defs.launch")
require("lib.actions.defs.resize")

local function enter_submap(name) return { "submap.enter", { name } } end

--- The four directions as actions that resize by `amount` pixels.
--- @param amount number
--- @return DirActions
local function resize_by(amount)
  return {
    left = { "resize.step", { "left", amount } },
    down = { "resize.step", { "down", amount } },
    up = { "resize.step", { "up", amount } },
    right = { "resize.step", { "right", amount } },
  }
end

Submap.define({
  name = "Resize",
  desc = "+Resize",
  enter = Config.leader .. " + R",

  escape = "reset",
  catchall = "stay",
  targets = true,

  hint = {
    { "Resize", { "resize.step", tiers = "speed" } },
    { "Window", { "resize.reset", label = "Reset" } },
    { "Mode", "submap.enter" },
  },

  binds = function()
    -- Straight to the other `targets` submaps, so the selection carries; BackSpace only goes back one step.
    local keys = {
      { "EQUAL", "resize.reset" },
      { "W", enter_submap("Windows"), "+Windows" },
      { "M", enter_submap("Move"), "+Move" },
    }
    for _, key in ipairs(Direction.speed_binds(resize_by, "Resize")) do
      keys[#keys + 1] = key
    end
    return keys
  end,
}).setup()
