--- Move submap — entered with SUPER+M.
--- H/J/K/L (+ arrow keys) move the focused window; modifier keys select step size:
---   none = 10 px, SHIFT = 100 px, CTRL = 1 px, CTRL+SHIFT = 300 px.
--- ESCAPE exits back to global.
--- @see modes.move.actions
local Config    = require("config")
local Direction = require("lib.key.direction")
local Move      = require("lib.actions.move")
local Submap    = require("lib.key.submap")

Submap.define({
  name = "Move",
  desc = "+Move",
  enter = Config.leader .. " + M",

  escape = "reset",
  catchall = "stay",

  on_enter = function()
    -- hl.dispatch(hl.dsp.exec_cmd("eww open hyprvim-move"))
  end,

  on_exit = function()
    -- hl.dispatch(hl.dsp.exec_cmd("eww close hyprvim-move"))
  end,

  binds = function()
    return Direction.speed_binds(Move.at, "Move")
  end,
}).setup()
