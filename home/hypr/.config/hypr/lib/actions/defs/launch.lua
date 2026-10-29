-- Actions for the launch keys: terminals, file managers, the menus and the task manager. The performers stay in
-- lib/actions/{cmd,menu}.lua and run on use, so a headless load needs neither Config nor the session, and a command that
-- follows Config (the file managers) reads it when it runs.
local Act = require("lib.act") ---@class ActionLib
local Defer = require("lib.actions.defer") ---@class Defer
local Scripts = require("lib.scripts") ---@class Scripts

Act.define("terminal.open", {
  label = "Terminal",
  intent = "Open a new terminal window.",
  run = Defer.call("lib.actions.cmd", "open_term"),
})

Act.define("terminal.bottom", {
  label = "Bottom Terminal",
  intent = "Open a terminal in the bottom half of the screen.",
  run = Defer.call("lib.actions.cmd", "bottom_terminal"),
})

Act.define("menu.ssh", {
  label = "SSH Select",
  intent = "Pick a host from the SSH config and connect in a terminal.",
  run = Defer.call("lib.actions.menu", "ssh"),
})

Act.define("files.open", {
  label = "File Manager",
  intent = "Open the graphical file manager.",
  run = function() require("lib.actions.cmd").run(require("config").app.gui_file_manager)() end,
})

Act.define("menu.drun", {
  label = "Open Application",
  intent = "Pick an application and start it.",
  run = Defer.call("lib.actions.menu", "drun"),
})

Act.define("menu.agents", {
  label = "Agent Sessions",
  intent = "Open the agent sessions popup.",
  run = Defer.call("lib.actions.menu", "agents"),
})

Act.define("menu.tmux", {
  label = "Tmux Project",
  intent = "Pick a tmux project and open its session.",
  run = Act.Cmd(Scripts.rofi_tmux),
})

Act.define("terminal.yazi", {
  label = "Yazi",
  intent = "Open Yazi in a new terminal.",
  run = Defer.call("lib.actions.cmd", "term", "yazi"),
})

Act.define("terminal.task_manager", {
  label = "Task Manager",
  intent = "Open btop in a new terminal.",
  run = Defer.call("lib.actions.cmd", "term", "btop"),
})

Act.define("submap.enter", {
  label = "Enter Submap",
  intent = "Switch to a key submap such as Bar or Groups.",
  params = { { name = "name", type = "string" } },
  run = function(name)
    local Submap = require("lib.key.submap")
    -- Submap.enter ignores an unknown name; here it must fail, or `hypr-act submap.enter Typo` exits 0 doing nothing.
    if not Submap.registry[name] then error("unknown submap '" .. name .. "'", 0) end
    Submap.enter(name)
  end,
})
