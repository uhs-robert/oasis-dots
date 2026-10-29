-- Actions for the Move submap: nudge the selected windows (lib/selection.lua), or the focused one when none is
-- selected, by a pixel step. Keyless; the Move rows bind them, one per direction and speed tier.
local Act = require("lib.act") ---@class ActionLib

Act.define("move.step", {
  label = "Nudge Window",
  intent = "Move every selected window, or the focused one when none is selected, by a number of pixels in a direction.",
  params = {
    { name = "dir", type = "enum", values = { "left", "down", "up", "right" } },
    { name = "amount", type = "int" },
  },
  run = function(dir, amount) require("lib.selection").for_selected(require("lib.actions.move").at(amount)[dir])() end,
})
