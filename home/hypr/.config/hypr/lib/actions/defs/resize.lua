-- Actions for the Resize submap. Keyless; the Resize rows bind them, one per direction and speed tier.
local Act = require("lib.act") ---@class ActionLib

Act.define("resize.step", {
  label = "Resize Window",
  intent = "Grow or shrink the focused window by a number of pixels in a direction.",
  params = {
    { name = "dir", type = "enum", values = { "left", "down", "up", "right" } },
    { name = "amount", type = "int" },
  },
  run = function(dir, amount) require("lib.actions.resize").at(amount)[dir]() end,
})

Act.define("resize.reset", {
  label = "Reset Size",
  intent = "Return the focused window to its layout size by floating and tiling it again.",
  run = function() require("lib.actions.resize").reset() end,
})
