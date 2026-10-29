--- Go submap
--- Each bind navigates to a window, workspace, or monitor

local Config = require("config") --- @class Config
local Submap = require("lib.key.submap") --- @class Submap
local Window = require("lib.actions.window") --- @class WindowActions
local Workspaces = require("lib.workspaces") --- @class Workspaces

-- The actions the rows name.
require("lib.actions.defs.apps")
require("lib.actions.defs.launch")
require("lib.actions.defs.pickers")
require("lib.actions.defs.tools")
require("lib.actions.defs.workspaces")

local function focus_app(app) return { "apps.focus", { app } } end

Submap.define({
  name = "Go",
  desc = "+Go",
  enter = Config.leader .. " + G",

  escape = "reset",
  catchall = "reset",

  binds = function()
    local rows = {
      -- stylua: ignore start
      { "TAB",       "workspace.focus_last" },
      { "A",         "picker.agents" },
      { "B",         focus_app("firefox"),                  "Browser" },
      { "C",         focus_app("tmux_config"),              "Tmuxifier Config" },
      { "M",         focus_app("betterbird"),               "Mail" }, { "P",         "menu.tmux",                           "Project" }, -- TODO: Convert to QS?
      { "Q",         focus_app("qutebrowser"),              "QuteBrowser" },
      { "S",         focus_app("slack"),                    "Slack" },
      { "SHIFT + S", focus_app("steam"),                    "Steam" },
      { "T",         focus_app("terminal"),                 "Terminal" },
      { "V",         "terminal.editor" },
      { "W",         "overview.search",                     "Search Windows" },
      { "Y",         focus_app("yazi"),                     "Yazi" },
      -- stylua: ignore end
    }

    for i, entry in ipairs(Config.monitors) do
      local sel = Workspaces.get_monitor_selector(entry)
      if sel then table.insert(rows, { tostring(i), Window.focus_by({ monitor = sel }), "Monitor " .. i }) end
    end

    return rows
  end,
}).setup()
