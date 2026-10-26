-- Actions for the Applications and Go submaps: focus-or-launch an app, open one, run a terminal tool, focus a window by
-- title. They take a name from a fixed list instead of a command, so `hypr-act` cannot be made to run arbitrary
-- commands. No default keys: the submap rows bind them.
local Act = require("lib.act") ---@class ActionLib

--- The keys of `set`, sorted: the values an enum param accepts.
--- @param set table<string, any>
--- @return string[]
local function names_of(set)
  local names = {}
  for name in pairs(set) do
    table.insert(names, name)
  end
  table.sort(names)
  return names
end

-- Must list every name in `Apps.map` (lib/actions/apps.lua); act_submap_rows.lua fails when one is missing.
local MAPPED_APPS = {
  "betterbird",
  "cliamp",
  "firefox",
  "hyprconfig",
  "protonplus",
  "qutebrowser",
  "slack",
  "steam",
  "terminal",
  "thunar",
  "tmux_config",
  "yazi",
}

Act.define("apps.focus", {
  label = "Focus or Launch App",
  intent = "Focus the app's window, or start the app when it has none.",
  params = { { name = "app", type = "enum", values = MAPPED_APPS } },
  run = function(app)
    local Apps = require("lib.actions.apps")
    Apps.focus_or_launch(Apps.map[app])()
  end,
})

-- Apps that are only started, never focused; the value is the command.
local OPENED_APPS = {
  bottles = "bottles",
  deluge = "deluge",
  discord = "discord",
  firefox = "firefox",
  gimp = "gimp",
  inkscape = "inkscape",
  libreoffice_calc = "libreoffice --calc",
  libreoffice_writer = "libreoffice --writer",
  qalculate = "qalculate-gtk",
  qutebrowser = "qutebrowser",
}

Act.define("apps.open", {
  label = "Open App",
  intent = "Start an app, even when it is already running.",
  params = { { name = "app", type = "enum", values = names_of(OPENED_APPS) } },
  run = function(app) require("lib.actions.apps").open(OPENED_APPS[app])() end,
})

-- window: "terminal" is a normal terminal window, "bottom" the half-height one; prefill types the command at the prompt
-- instead of running it.
local TERMINAL_TOOLS = {
  aria2tui = { window = "terminal" },
  abtop = { window = "terminal" },
  doggo = { window = "bottom", prefill = true },
  gdu = { window = "bottom" },
  gping = { window = "bottom", prefill = true },
  lazyjournal = { window = "bottom" },
  qalc = { window = "bottom" },
  xh = { window = "bottom", prefill = true },
}

Act.define("terminal.tool", {
  label = "Terminal Tool",
  intent = "Run a command-line tool in a terminal: aria2tui, abtop, doggo, gdu, gping, lazyjournal, qalc or xh.",
  params = { { name = "tool", type = "enum", values = names_of(TERMINAL_TOOLS) } },
  run = function(tool)
    local Cmd = require("lib.actions.cmd")
    local spec = TERMINAL_TOOLS[tool]
    if spec.window == "terminal" then
      Cmd.term(tool)()
    else
      Cmd.bottom_terminal(tool, spec.prefill)()
    end
  end,
})

Act.define("terminal.editor", {
  label = "Editor",
  intent = "Open the configured editor in a new terminal.",
  run = function() require("lib.actions.cmd").term(require("config").app.editor or "nvim")() end,
})

local WINDOW_TITLES = {
  meeting = "title:(?i).*Meet.*",
  youtube = "title:(?i).*youtube.*",
}

Act.define("window.focus_match", {
  label = "Focus Window by Title",
  intent = "Focus the window whose title matches: a video call (meeting) or YouTube.",
  params = { { name = "name", type = "enum", values = { "meeting", "youtube" } } },
  run = function(name) require("lib.actions.window").focus_by({ window = WINDOW_TITLES[name] })() end,
})
