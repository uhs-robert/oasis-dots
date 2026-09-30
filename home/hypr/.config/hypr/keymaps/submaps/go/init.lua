--- Go submap
--- Each bind navigates to a window, workspace, or monitor

local Config = require("config") --- @class Config
local Cmd = require("lib.actions.cmd") ---@class Cmd
local Apps = require("lib.actions.apps") --- @class Apps
local Menu = require("lib.actions.menu") --- @class Menu
local Submap = require("lib.key.submap") --- @class Submap
local Window = require("lib.actions.window") --- @class WindowActions
local Workspace = require("lib.actions.workspace") --- @class WorkspaceActions
local Workspaces = require("lib.workspaces") --- @class Workspaces
local Scripts = require("lib.scripts") ---@class Scripts

local APP = Apps.map

local function popup(name) return Cmd.run(Scripts.qs_ipc .. " call popup open " .. name) end

local SELECTORS = {
  youtube = { window = "title:(?i).*youtube.*" },
  meeting = { window = "title:(?i).*Meet.*" },
}

Submap.define({
  name = "Go",
  desc = "+Go",
  enter = Config.leader .. " + G",

  escape = "reset",
  catchall = "reset",

  binds = function()
    local rows = {
      -- stylua: ignore start
      { "TAB",       Workspace.focus_last(),                "Last Workspace" },
      { "A",         Menu.agents(),                         "Agent Sessions" },
      { "B",         Apps.focus_or_launch(APP.firefox),     "Browser" },
      { "C",         Apps.focus_or_launch(APP.tmux_config), "Tmuxifier Config" },
      { "SHIFT + C", Apps.focus_or_launch(APP.tmux_client),  "Tmuxifier Client" },
      { "F",         Apps.focus_or_launch(APP.yazi),        "Files" },
      { "SHIFT + F", Apps.focus_or_launch(APP.thunar),      "Thunar" },
      { "H",         Apps.focus_or_launch(APP.hyprconfig),  "Hypr Config" },
      { "M",         Apps.focus_or_launch(APP.betterbird),  "Mail" },
      { "SHIFT + M", Window.focus_by(SELECTORS.meeting),    "Meeting" },
      { "P",         Menu.tmux(),                           "Project" },
      { "Q",         Apps.focus_or_launch(APP.qutebrowser), "QuteBrowser" },
      { "S",         Apps.focus_or_launch(APP.slack),       "Slack" },
      { "SHIFT + S", Apps.focus_or_launch(APP.steam),       "Steam" },
      { "T",         Apps.focus_or_launch(APP.terminal),    "Terminal" },
      { "U",         Apps.focus_or_launch(APP.tmux_uphill), "Tmuxifier UpHill" },
      { "W",         Menu.hyprwindow(),                     "Window" },
      { "Y",         Window.focus_by(SELECTORS.youtube),    "Youtube" },
      -- stylua: ignore end
    }

    for i, entry in ipairs(Config.monitors) do
      local sel = Workspaces.get_monitor_selector(entry)
      if sel then table.insert(rows, { tostring(i), Window.focus_by({ monitor = sel }), "Monitor " .. i }) end
    end

    return rows
  end,
}).setup()
