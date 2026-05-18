--- Resize submap — entered with SUPER+R.
--- H/J/K/L (+ arrow keys) resize the focused window; modifier keys select step size:
---   none = 10 px, SHIFT = 100 px, CTRL = 1 px, CTRL+SHIFT = 300 px.
--- ESCAPE exits back to global. EQUAL resets window size.
--- @see modes.resize.actions
local Config = require("config")
local Direction = require("lib.key.direction")
local Resize = require("lib.actions.resize")
local Submap = require("lib.key.submap")

Submap.define({
  name = "Resize",
  desc = "+Resize",
  enter = Config.leader .. " + R",

  escape = "reset",
  catchall = "stay",

  on_enter = function()
    -- Example:
    -- hl.dispatch(hl.dsp.exec_cmd("eww open hyprvim-resize"))
  end,

  on_exit = function()
    -- Example:
    -- hl.dispatch(hl.dsp.exec_cmd("eww close hyprvim-resize"))
  end,

  binds = function()
    local keys = {
      { "EQUAL", Resize.reset, "Reset Size" },
    }
    for _, key in ipairs(Direction.speed_binds(Resize.at, "Resize")) do keys[#keys + 1] = key end
    return keys
  end,
}).setup()
