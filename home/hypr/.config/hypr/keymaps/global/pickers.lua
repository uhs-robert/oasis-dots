local Act = require("lib.act") ---@class ActionLib

Act.load_defs({ "pickers" })

Act.bind("picker.clipboard", { key = { key = "CTRL + V", leader = true } })
Act.bind("picker.directory", { key = { key = "CTRL + SPACE", leader = true } })
Act.bind("picker.emoji", { key = { key = "CTRL + E", leader = true } })
Act.bind("picker.agents", { key = { key = "A", leader = true } })
Act.bind("hyprvim.terminal", { key = { key = "SHIFT + SEMICOLON", leader = true } })
Act.bind("hyprvim.jump_mark", { key = { key = "APOSTROPHE", leader = true } })
Act.bind("hyprvim.edit_selection", { key = { key = "N", leader = true } })
