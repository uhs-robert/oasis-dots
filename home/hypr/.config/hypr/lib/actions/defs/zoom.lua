-- Keyless zoom actions beyond the Z key (`zoom.toggle`, tools.lua). The deltas step the live magnifier.
local Act = require("lib.act") ---@class ActionLib
local Ipc = Act.Ipc

Act.define("zoom.step", {
  label = "Zoom Step",
  intent = "Change the zoom level by delta steps; negative zooms out.",
  params = { { name = "delta", type = "int" } },
  run = Ipc("zoom", "step", "{delta}"),
})

Act.define("zoom.size", {
  label = "Zoom Lens Size",
  intent = "Change the size of the zoom lens by delta steps; negative shrinks it.",
  params = { { name = "delta", type = "int" } },
  run = Ipc("zoom", "size", "{delta}"),
})

Act.define("zoom.full", {
  label = "Zoom Full Screen",
  intent = "Switch the magnifier between the lens and the whole screen.",
  run = Ipc("zoom", "full"),
})
