--- Move submap
--- Each bind moves the current active window

local Config = require("config") ---@class Config
local Direction = require("lib.key.direction") ---@class Direction
local Move = require("lib.actions.move") ---@class Move
local Submap = require("lib.key.submap") ---@class Submap

Submap.define({
  name = "Move",
  desc = "+Move",
  enter = Config.leader .. " + M",

  escape = "reset",
  catchall = "stay",

  binds = function() return Direction.speed_binds(Move.at, "Move") end,
}).setup()
