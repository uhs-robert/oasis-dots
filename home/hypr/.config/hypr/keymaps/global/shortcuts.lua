local Act = require("lib.act") ---@class ActionLib

require("lib.actions.defs.launch")

Act.bind("terminal.open", { key = { key = "RETURN", leader = true } })
Act.bind("terminal.bottom", { key = { key = "SHIFT + RETURN", leader = true } })
Act.bind("menu.ssh", { key = { key = "CTRL + RETURN", leader = true } })
Act.bind("files.open", { key = { key = "E", leader = true } })
Act.bind("menu.drun", { key = { key = "O", leader = true } })
Act.bind("menu.agents", { key = { key = "CTRL + A", leader = true } })
Act.bind("terminal.yazi", { key = { key = "Y", leader = true } })
Act.bind("terminal.task_manager", { key = "CTRL + SHIFT + ESCAPE" })

-- keep: the Bar submap takes over the next key, so entering it must not reset the one it came from.
Act.bind("submap.enter", { key = { key = "B", leader = true }, args = { "Bar" }, desc = "+Bar", keep = true })
