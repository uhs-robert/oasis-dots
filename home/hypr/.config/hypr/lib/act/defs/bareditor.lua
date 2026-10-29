-- Keyless actions for the bar editor: it has no hotkey (the Settings "Edit bar" row and these ids open it).
local Act = require("lib.act") ---@class ActionLib
local Ipc = Act.Ipc

Act.define("bareditor.open", {
  label = "Edit Bar",
  intent = "Open the bar editor on a monitor's bar (for example DP-1); with no monitor, the focused one.",
  params = { { name = "monitor", type = "string", default = "" } },
  run = Ipc("bareditor", "open", "{monitor}"),
})

Act.define("bareditor.toggle", {
  label = "Toggle Bar Editor",
  intent = "Open the bar editor on the focused monitor, or close it when it is open.",
  run = Ipc("bareditor", "toggle"),
})

Act.define("bareditor.close", {
  label = "Close Bar Editor",
  intent = "Close the bar editor.",
  run = Ipc("bareditor", "close"),
})
