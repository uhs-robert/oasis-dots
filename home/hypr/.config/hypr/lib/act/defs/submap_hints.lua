-- The hint bar's own key. Keyless: Submap.define binds it on `i` in every submap that has a hint, and loads this file.
local Act = require("lib.act") ---@class ActionLib

Act.define("submap.hints_toggle", {
  label = "Toggle Hint Panel",
  intent = "Hide or show the submap hint bar until the submap is left; Submap.define binds it on `i` in every submap with a hint.",
  run = Act.Ipc("submap_hints", "toggle"),
})
