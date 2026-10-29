-- Keyless screenshot actions that talk to the bar's menu. `screenshot.take` and `screenshot.pixel` (tools.lua) have the
-- global keys, and run the script that falls back to rofi.
local Act = require("lib.act") ---@class ActionLib
local Ipc = Act.Ipc

Act.define("screenshot.menu", {
  label = "Screenshot Menu",
  intent = "Open the screenshot and recording menu; while a scrolling capture runs, finish it instead.",
  run = Ipc("screenshot", "open"),
})

Act.define("screenshot.select", {
  label = "Select Region",
  intent = "Pick a screen region; the preset chooses the toolbar or what to do on confirm.",
  params = {
    { name = "frozen", type = "bool" },
    { name = "preset", type = "enum", values = { "toolbar", "ocr", "record", "scroll_text", "scroll_image" } },
  },
  run = Ipc("screenshot", "select", "{frozen}", "{preset}"),
})

Act.define("screenshot.stop_recording", {
  label = "Stop Recording",
  intent = "Stop the screen recording that is running.",
  run = Ipc("screenshot", "stop_recording"),
})
