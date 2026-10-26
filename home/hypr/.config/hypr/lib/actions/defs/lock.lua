-- The lock screen as an action. The id says "open", not "lock", so `lock.open` reads as the screen it raises.
local Act = require("lib.act") ---@class ActionLib
local Ipc = Act.Ipc

Act.define("lock.open", {
  label = "Lock Screen",
  intent = "Lock the session now, with no confirmation.",
  run = Ipc("lock", "lock"),
})
