-- Actions for the Move submap: nudge the focused window by a pixel step. Keyless; the Move rows bind them, one per
-- direction and speed tier.
local Act = require("lib.act") ---@class ActionLib

Act.define("move.step", {
  label = "Nudge Window",
  intent = "Move the focused window by a number of pixels in a direction.",
  params = {
    { name = "dir", type = "enum", values = { "left", "down", "up", "right" } },
    { name = "amount", type = "int" },
  },
  run = function(dir, amount) require("lib.actions.move").at(amount)[dir]() end,
})

Act.define("window.float_toggle", {
  label = "Toggle Floating",
  intent = "Float the focused window, or tile it again.",
  run = function() require("lib.actions.window").float_toggle()() end,
})
