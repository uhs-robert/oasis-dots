--- Move submap
--- Each bind moves the current active window

local Config = require("config") ---@class Config
local Direction = require("lib.key.direction") ---@class Direction
local Submap = require("lib.key.submap") ---@class Submap

-- The actions the rows name.
require("lib.actions.defs.move")
require("lib.actions.defs.windows")

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

  hint = {
    { "Move", { "move.step", tiers = "speed" } },
    { "Window", { "window.float_toggle", label = "Float" } },
  },

  binds = function()
    local keys = {
      { "F", "window.float_toggle" },
    }

    for _, key in ipairs(Direction.speed_binds(nudge, "Move")) do
      keys[#keys + 1] = key
    end

    return keys
  end,
}).setup()
