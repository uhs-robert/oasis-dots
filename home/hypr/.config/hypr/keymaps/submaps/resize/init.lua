--- Resize submap
--- Each bind resizes the active window

local Config = require("config") ---@class Config
local Direction = require("lib.key.direction") ---@class Direction
local Submap = require("lib.key.submap") ---@class Submap

-- The actions the rows name.
require("lib.actions.defs.resize")

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

  hint = {
    { "Resize", "resize.step" },
    { "Window", { "resize.reset", label = "Reset" } },
  },

  binds = function()
    local keys = {
      { "EQUAL", "resize.reset" },
    }
    for _, key in ipairs(Direction.speed_binds(resize_by, "Resize")) do
      keys[#keys + 1] = key
    end
    return keys
  end,
}).setup()
