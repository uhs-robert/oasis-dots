-- One action for every bar popup. Leader and Bar rows pass the popup name.
local Act = require("lib.act") ---@class ActionLib

Act.define("popup.open", {
  label = "Open Popup",
  intent = "Open a bar popup by name (clock, network, volume, notifications, start, settings, ...) on the focused monitor.",
  params = { { name = "name", type = "string" } },
  run = Act.Ipc("popup", "open", "{name}"),
})
