-- home/hypr/.config/hypr/config/system/keys/submaps/go.lua

local Config = require("config") --- @class Config
local SubBind = require("lib.submap_bind") --- @class SubBind
local SUBMAP = require("config.system.keys.submap").map
local Workspaces = require("lib.workspaces") --- @class Workspaces
local Scripts = require("lib.scripts") --- @class Scripts

local MENU = Config.app.menu
local TERM = Config.app.term

--- Go
hl.define_submap(SUBMAP.go.name, function()
  -- stylua: ignore start
  SubBind.exec("TAB", function() hl.dispatch(hl.dsp.focus({ workspace = "previous" })) end, "Last workspace")
  SubBind.run("A",   MENU .. " -i -show drun",       "App launcher")
  SubBind.run("W",   MENU .. " -i -show hyprwindow", "Window")
  SubBind.run("P",   Scripts.rofi_tmux,              "Project") -- TODO: Move to rofi dir
  SubBind.exec("Y", function() hl.dispatch(hl.dsp.focus({ window = "title:(?i).*youtube.*" })) end, "Youtube")

  -- !--- Apps ---
  SubBind.focus_or_launch("B",         { program = "firefox",     class = "org.mozilla.firefox" },                                                    "Browser")
  SubBind.focus_or_launch("C",         { program = TERM, title = "Tmux Config",             cmd = TERM .. ' -e tmuxifier load-session config' },      "Tmuxifier Config")
  SubBind.focus_or_launch("SHIFT + C", { program = TERM, title = "Tmux Client App", cmd = TERM .. ' -e tmuxifier load-session client-dev' },      "Tmuxifier Client")
  SubBind.focus_or_launch("F",         { program = TERM, class = "yazi",                    cmd = TERM .. ' --class yazi -e yazi' },                  "Files")
  SubBind.focus_or_launch("SHIFT + F", { program = "dolphin",     class = "org.kde.dolphin" },                                                        "Dolphin")
  SubBind.focus_or_launch("H",         { program = TERM, class = "yazi",              cmd = TERM .. ' --class hyprconfig -e yazi ~/.config/hypr' },   "Hypr Config")
  SubBind.focus_or_launch("M",         { program = "betterbird",  class = "eu.betterbird.Betterbird", cmd = 'flatpak run eu.betterbird.Betterbird' }, "Mail")
  SubBind.focus_or_launch("Q",         { program = "qutebrowser", class = "org.qutebrowser.qutebrowser" },                                            "QuteBrowser")
  SubBind.focus_or_launch("S",         { program = "slack",       class = "Slack" },                                                                  "Slack")
  SubBind.focus_or_launch("T",         { program = TERM, exclude_title = "Tmux" },                                                                    "Terminal")
  SubBind.focus_or_launch("U",         { program = TERM, title = "Tmux UpHill",             cmd = TERM .. ' -e tmuxifier load-session uphill' },      "Tmuxifier UpHill")
  -- stylua: ignore end

  -- !--- Monitors ---
  for i, entry in ipairs(Config.monitors) do
    local sel = Workspaces.get_monitor_selector(entry)
    if sel then SubBind.exec(tostring(i), function() hl.dispatch(hl.dsp.focus({ monitor = sel })) end, "Monitor " .. i) end
  end

  SubBind.bind_exits({ swallow_mispress = true })
end)
