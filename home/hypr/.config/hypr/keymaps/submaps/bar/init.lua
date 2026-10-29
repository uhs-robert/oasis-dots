--- Bar submap
--- Opens a Quickshell bar popup on the focused monitor, then hands keys to the popup

local Submap = require("lib.key.submap") ---@class Submap
local BarRows = require("keymaps.submaps.bar.rows") ---@class BarRows

Submap.define({
  name = "Bar",
  desc = "+Bar",

  escape = "reset",
  catchall = "reset",

  binds = BarRows.binds(),
}).setup()
