-- Keyless actions for the Settings popup. `settings.open` with an empty section reopens the last one shown.
local Act = require("lib.act") ---@class ActionLib
local Ipc = Act.Ipc

Act.define("settings.open", {
  label = "Open Settings",
  intent = "Open Settings on a section such as colors or wallpaper; with no section, the last one shown.",
  params = { { name = "section", type = "string", default = "" } },
  run = Ipc("settings", "open", "{section}"),
})

Act.define("settings.toggle", {
  label = "Toggle Settings",
  intent = "Open Settings, or close it when it is open.",
  run = Ipc("settings", "toggle"),
})
