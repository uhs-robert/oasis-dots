-- Actions for the launch keys: terminals, file managers, the menus and the task manager. The performers stay in
-- lib/actions/{cmd,menu}.lua and run on use, so a headless load needs neither Config nor the session, and a command that
-- follows Config (the file managers) reads it when it runs.
local Act = require("lib.act") ---@class ActionLib
local Defer = require("lib.actions.defer") ---@class Defer

Act.define("terminal.open", {
  label = "Terminal",
  intent = "Open a new terminal window.",
  key = { key = "RETURN", leader = true },
  run = Defer.call("lib.actions.cmd", "open_term"),
})

Act.define("terminal.bottom", {
  label = "Bottom Terminal",
  intent = "Open a terminal in the bottom half of the screen.",
  key = { key = "SHIFT + RETURN", leader = true },
  run = Defer.call("lib.actions.cmd", "bottom_terminal"),
})

Act.define("menu.ssh", {
  label = "SSH Select",
  intent = "Pick a host from the SSH config and connect in a terminal.",
  key = { key = "CTRL + RETURN", leader = true },
  run = Defer.call("lib.actions.menu", "ssh"),
})

Act.define("menu.run_script", {
  label = "Run Script",
  intent = "Pick a program from the PATH and run it.",
  key = { key = "ALT + RETURN", leader = true },
  run = Defer.call("lib.actions.menu", "run"),
})

Act.define("files.open", {
  label = "File Manager",
  intent = "Open the graphical file manager.",
  key = { key = "E", leader = true },
  run = function() require("lib.actions.cmd").run(require("config").app.gui_file_manager)() end,
})

Act.define("terminal.tui_files", {
  label = "TUI File Manager",
  intent = "Open the terminal file manager in a new terminal.",
  key = { key = "SHIFT + E", leader = true },
  run = function() require("lib.actions.cmd").term(require("config").app.tui_file_manager)() end,
})

Act.define("menu.drun", {
  label = "Open Application",
  intent = "Pick an application and start it.",
  key = { key = "O", leader = true },
  run = Defer.call("lib.actions.menu", "drun"),
})

Act.define("menu.cli", {
  label = "Run CLI Tool",
  intent = "Pick a program from the PATH and run it in a terminal that stays open.",
  key = { key = "CTRL + O", leader = true },
  run = Defer.call("lib.actions.menu", "cli"),
})

Act.define("menu.agents", {
  label = "Agent Sessions",
  intent = "Open the agent sessions popup.",
  key = { key = "CTRL + A", leader = true },
  run = Defer.call("lib.actions.menu", "agents"),
})

Act.define("terminal.yazi", {
  label = "Yazi",
  intent = "Open Yazi in a new terminal.",
  key = { key = "Y", leader = true },
  run = Defer.call("lib.actions.cmd", "term", "yazi"),
})

Act.define("terminal.task_manager", {
  label = "Task Manager",
  intent = "Open btop in a new terminal.",
  key = "CTRL + SHIFT + ESCAPE",
  run = Defer.call("lib.actions.cmd", "term", "btop"),
})

-- Keyless: a submap name is a param, so the key that enters one is bound with Act.bind where the key is chosen.
Act.define("submap.enter", {
  label = "Enter Submap",
  intent = "Switch to a key submap such as Bar or Groups.",
  params = { { name = "name", type = "string" } },
  run = function(name) require("lib.key.submap").enter(name) end,
})
