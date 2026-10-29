-- The power prompt as an action. `confirm` only drops the prompt; the bar runs the power action after the person
-- accepts it. IPC `power run`, which skips the prompt, is deliberately not an action.
local Act = require("lib.act") ---@class ActionLib
local Ipc = Act.Ipc

Act.define("power.confirm", {
  label = "Power Prompt",
  intent = "Ask before locking, logging out, rebooting or powering off.",
  params = { { name = "kind", type = "enum", values = { "lock", "logout", "reboot", "poweroff" } } },
  run = Ipc("power", "confirm", "{kind}"),
})
