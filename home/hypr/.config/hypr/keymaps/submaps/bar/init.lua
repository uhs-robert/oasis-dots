--- Bar submap
--- Opens a Quickshell bar popup on the focused monitor, then hands keys to the popup

local Submap = require("lib.key.submap") ---@class Submap
local Popups = require("lib.actions.popups") ---@class Popups

Submap.define({
  name = "Bar",
  desc = "+Bar",

  escape = "reset",
  catchall = "reset",

  binds = Popups.binds(),
}).setup()
