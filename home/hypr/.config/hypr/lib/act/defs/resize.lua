-- Actions for the Resize submap, on the selected windows (lib/selection.lua) or the focused one when none is
-- selected. Keyless; the Resize rows bind them, one per direction and speed tier.
local Act = require("lib.act") ---@class ActionLib

Act.define("resize.step", {
  label = "Resize Window",
  intent = "Grow or shrink every selected window, or the focused one when none is selected, by a number of pixels in a direction.",
  params = {
    { name = "dir", type = "enum", values = { "left", "down", "up", "right" } },
    { name = "amount", type = "int" },
  },
  run = function(dir, amount) require("lib.selection").for_selected(require("lib.desktop.resize").at(amount)[dir])() end,
})

Act.define("resize.reset", {
  label = "Reset Size",
  intent = "Return every selected window, or the focused one when none is selected, to its layout size by floating and tiling it again.",
  run = function() require("lib.selection").for_selected(require("lib.desktop.resize").reset)() end,
})
