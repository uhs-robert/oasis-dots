local Act = require("lib.act") ---@class ActionLib

-- The launch keys (terminals, file managers, menus, task manager) bind their own keys when this file loads.
require("lib.actions.defs.launch")

-- keep: the Bar submap takes over the next key, so entering it must not reset the one it came from.
Act.bind("submap.enter", { key = { key = "B", leader = true }, args = { "Bar" }, desc = "+Bar", keep = true })
