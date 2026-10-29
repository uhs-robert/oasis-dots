local Act = require("lib.act") ---@class ActionLib

Act.load_defs({ "tools" })

Act.bind("screenshot.take", { key = { key = "Print", universal = true } })
Act.bind("screenshot.take", { key = { key = "I", leader = true } })
Act.bind("screenshot.pixel", { key = { key = "P", leader = true } })
Act.bind("zoom.toggle", { key = { key = "Z", leader = true } })
Act.bind("voice.dictate", { key = { key = "PERIOD", leader = true } })
Act.bind("voice.command", { key = { key = "COMMA", leader = true } })
Act.bind("voice.stop", { key = { key = "SHIFT + COMMA", leader = true } })
Act.bind("voice.rapid", { key = { key = "CTRL + COMMA", leader = true } })
Act.bind("voice.wake", { key = { key = "CTRL + PERIOD", leader = true } })
Act.bind("picker.passwords", { key = { key = "CTRL + P", leader = true } })
Act.bind("overview.search", { key = { key = "T", leader = true } })
Act.bind("overview.move", { key = { key = "SHIFT + T", leader = true } })
Act.bind("overview.open", { key = "ALT + TAB" })
Act.bind("overview.open", { key = { key = "TAB", leader = true } })
Act.bind("tmux.overview", { key = "ALT + GRAVE" })
