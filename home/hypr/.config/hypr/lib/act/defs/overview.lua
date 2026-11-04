-- Keyless open and close for the workspace overview beyond the ones with global keys (`overview.*` in tools.lua).
local Act = require("lib.act") ---@class ActionLib
local Ipc = Act.Ipc

Act.define("overview.toggle", {
  label = "Toggle Overview",
  intent = "Open the workspace overview, or close it when it is open.",
  run = Ipc("overview", "toggle"),
})

Act.define("overview.close", {
  label = "Close Overview",
  intent = "Close the workspace overview.",
  run = Ipc("overview", "close"),
})
