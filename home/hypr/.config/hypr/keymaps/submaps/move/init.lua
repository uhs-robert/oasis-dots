--- Move submap
--- Each bind moves the current active window

local Config = require("config") ---@class Config
local Direction = require("lib.key.direction") ---@class Direction
local Move = require("lib.actions.move") ---@class Move
local Submap = require("lib.key.submap") ---@class Submap
local Window = require("lib.actions.window") ---@class WindowActions

Submap.define({
  name = "Move",
  desc = "+Move",
  enter = Config.leader .. " + M",

  escape = "reset",
  catchall = "stay",

  binds = function()
    -- stylua: ignore start
    local keys = {
      { "F", Window.float_toggle(), "Toggle Floating" },
    }
    -- stylua: ignore end

    for _, key in ipairs(Direction.speed_binds(Move.at, "Move")) do
      keys[#keys + 1] = key
    end

    return keys
  end,
}).setup()
