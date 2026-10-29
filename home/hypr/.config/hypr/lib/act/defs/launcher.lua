-- Keyless actions that open the bar's pickers by name. Unlike `picker.clipboard` and the others in pickers.lua, these
-- have no rofi fallback: a bar without the provider ignores the call. `choices` is left out, since it needs a spec file
-- its caller writes.
local Act = require("lib.act") ---@class ActionLib
local Ipc = Act.Ipc

local PICKERS = { "apps", "clipboard", "dirs", "emoji", "keybinds" }

Act.define("picker.open", {
  label = "Open Picker",
  intent = "Open the named bar picker: apps, clipboard, dirs, emoji or keybinds.",
  params = { { name = "name", type = "enum", values = PICKERS } },
  run = Ipc("picker", "open", "{name}"),
})

Act.define("picker.toggle", {
  label = "Toggle Picker",
  intent = "Open the named bar picker, or close it when it is open.",
  params = { { name = "name", type = "enum", values = PICKERS } },
  run = Ipc("picker", "toggle", "{name}"),
})

Act.define("picker.close", {
  label = "Close Picker",
  intent = "Close the open bar picker.",
  run = Ipc("picker", "close"),
})
