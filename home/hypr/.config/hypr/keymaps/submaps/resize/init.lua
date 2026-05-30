--- Resize submap
--- Each bind resizes the active window

local Config = require("config") ---@class Config
local Direction = require("lib.key.direction") ---@class Direction
local Resize = require("lib.actions.resize") ---@class Resize
local Submap = require("lib.key.submap") ---@class Submap

Submap.define({
  name = "Resize",
  desc = "+Resize",
  enter = Config.leader .. " + R",

  escape = "reset",
  catchall = "stay",

  binds = function()
    local keys = {
      { "EQUAL", Resize.reset, "Reset Size" },
      { "SHIFT + SLASH", function() require("lua.plugins.hyprvim").whichkey.toggle() end, "WhichKey" },
    }
    for _, key in ipairs(Direction.speed_binds(Resize.at, "Resize")) do
      keys[#keys + 1] = key
    end
    return keys
  end,
}).setup()
