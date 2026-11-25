-- Keyless music mode action. `set` is for voice (voxcmd, bar-music-mode PR4), `state` is a query.
local Act = require("lib.act") ---@class ActionLib
local Ipc = Act.Ipc

Act.define("music.toggle", {
  label = "Toggle Music Mode",
  intent = "Switch music mode (the playing music drawn in the screen frame) on or off.",
  run = Ipc("music", "toggle"),
})
