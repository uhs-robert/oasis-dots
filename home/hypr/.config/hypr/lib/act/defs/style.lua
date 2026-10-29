-- Keyless actions for the bar style. `style.set` takes any string because the style list is the bar's, not an enum
-- this file could keep in step.
local Act = require("lib.act") ---@class ActionLib
local Ipc = Act.Ipc

Act.define("style.cycle", {
  label = "Next Style",
  intent = "Switch the bar to the next style in its list, wrapping at the end.",
  run = Ipc("style", "cycle"),
})

Act.define("style.set", {
  label = "Set Style",
  intent = "Switch the bar to the named style, for example oasis or crt.",
  params = { { name = "name", type = "string" } },
  run = Ipc("style", "set", "{name}"),
})
