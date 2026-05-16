--- Go submap — entered with SUPER+G.
--- Each bind navigates to a window, workspace, or monitor then exits (oneshot via catchall = "reset").
--- ESCAPE exits without action.
local Config     = require("config")
local Go         = require("lib.actions.go")
local Scripts    = require("lib.scripts")
local Submap     = require("lib.key.submap")
local Window     = require("lib.actions.window")
local Workspace  = require("lib.actions.workspace")
local Workspaces = require("lib.workspaces")

local MENU = Config.app.menu
local TERM = Config.app.term

return Submap.define({
  name  = "Go",
  desc  = "+Go",
  enter = Config.leader .. " + G",

  escape   = "reset",
  catchall = "reset",

  binds = function()
    local rows = {
      -- stylua: ignore start
      { "TAB",       Workspace.focus_last(),                                                                                                   "Last Workspace" },
      { "A",         Go.run(MENU .. " -i -show drun"),                                                                                        "App Launcher" },
      { "W",         Go.run(MENU .. " -i -show hyprwindow"),                                                                                   "Window" },
      { "P",         Go.run(Scripts.rofi_tmux),                                                                                                "Project" },
      { "Y",         Window.focus_by({ window = "title:(?i).*youtube.*" }),                                                                    "Youtube" },

      { "B",         Go.focus_or_launch({ program = "firefox",     class = "org.mozilla.firefox" }),                                          "Browser" },
      { "C",         Go.focus_or_launch({ program = TERM, title = "Tmux Config",             cmd = TERM .. " -e tmuxifier load-session config" }),  "Tmuxifier Config" },
      { "SHIFT + C", Go.focus_or_launch({ program = TERM, title = "Tmux Client App", cmd = TERM .. " -e tmuxifier load-session client-dev" }),  "Tmuxifier Client" },
      { "F",         Go.focus_or_launch({ program = TERM, class = "yazi",                    cmd = TERM .. " --class yazi -e yazi" }),         "Files" },
      { "SHIFT + F", Go.focus_or_launch({ program = "dolphin",     class = "org.kde.dolphin" }),                                              "Dolphin" },
      { "H",         Go.focus_or_launch({ program = TERM, class = "hyprconfig",              cmd = TERM .. " --class hyprconfig -e yazi ~/.config/hypr" }), "Hypr Config" },
      { "M",         Go.focus_or_launch({ program = "betterbird",  class = "eu.betterbird.Betterbird", cmd = "flatpak run eu.betterbird.Betterbird" }), "Mail" },
      { "Q",         Go.focus_or_launch({ program = "qutebrowser", class = "org.qutebrowser.qutebrowser" }),                                  "QuteBrowser" },
      { "S",         Go.focus_or_launch({ program = "slack",       class = "Slack" }),                                                        "Slack" },
      { "T",         Go.focus_or_launch({ program = TERM, exclude_title = "Tmux" }),                                                          "Terminal" },
      { "U",         Go.focus_or_launch({ program = TERM, title = "Tmux UpHill",             cmd = TERM .. " -e tmuxifier load-session uphill" }), "Tmuxifier UpHill" },
      -- stylua: ignore end
    }

    for i, entry in ipairs(Config.monitors) do
      local sel = Workspaces.get_monitor_selector(entry)
      if sel then
        table.insert(rows, { tostring(i), Window.focus_by({ monitor = sel }), "Monitor " .. i })
      end
    end

    return rows
  end,
})
