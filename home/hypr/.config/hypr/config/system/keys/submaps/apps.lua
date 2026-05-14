-- home/hypr/.config/hypr/keys/submaps/apps.lua

local Config = require("config")
local Bind = require("lib.submap_bind")
local SUBMAP = require("config.system.keys.submap").map

local MENU = Config.app.menu
local TERM = Config.app.term

--- Applications
hl.define_submap(SUBMAP.applications.name, function()
  local email = "eu.betterbird.Betterbird"

  -- !--- Shortcuts ---
  Bind.run("SPACE", MENU .. " -i -show hyprwindow", "Find window by name")
  Bind.run("SLASH", MENU .. " -i -show drun", "Search applications")

  -- !--- Apps ---
  Bind.run("B", "bottles", "Bottles")
  Bind.run("C", "qalculate-gtk", "Calculator")
  Bind.run("D", "deluge", "Deluge")
  Bind.run("SHIFT + D", TERM .. " -e aria2tui", "Aria2tui")
  Bind.run("F", "firefox", "Firefox")
  Bind.run("G", "gimp", "Gimp")
  Bind.run("I", "inkscape", "Inkscape")
  Bind.run("K", "kate", "Kate")
  Bind.focus_or_launch("M", { program = "betterbird", class = email, cmd = "flatpak run " .. email }, "Mail")
  Bind.run("N", TERM .. " -e nvim", "NeoVim")
  Bind.run("SHIFT + N", TERM .. " -e newsboat", "Newsboat")
  Bind.run("P", "flatpak run com.vysp3r.ProtonPlus", "ProtonPlus")
  Bind.run("Q", "qutebrowser", "QuteBrowser")
  Bind.focus_or_launch("R", { program = "cliamp", title = "cliamp", cmd = TERM .. " -e cliamp" }, "Radio (Cliamp)")
  Bind.run("SHIFT + S", "steam", "Steam")
  Bind.focus_or_launch("S", { program = "slack", class = "Slack" }, "Slack")
  Bind.run("V", "code", "VS Code")
  Bind.run("W", "libreoffice --writer", "LibreOffice Writer")
  Bind.run("X", "libreoffice --calc", "LibreOffice Calc")

  Bind.set_escape(SUBMAP.applications)
  hl.bind("Escape", hl.dsp.submap("reset"))
end)

--- Go
hl.define_submap(SUBMAP.go.name, function()
  -- stylua: ignore start
  Bind.exec("TAB", function() hl.dispatch(hl.dsp.focus({ workspace = "previous" })) end, "Last workspace")
  Bind.run("A",   MENU .. " -i -show drun",       "App launcher")
  Bind.run("W",   MENU .. " -i -show hyprwindow", "Window")
  Bind.run("P",   "~/.config/hypr/scripts/rofi-tmux.sh", "Project") -- TODO: Move to rofi dir
  Bind.exec("Y", function() hl.dispatch(hl.dsp.focus({ window = "title:(?i).*youtube.*" })) end, "Youtube")

  -- !--- Apps ---
  Bind.focus_or_launch("B",         { program = "firefox",     class = "org.mozilla.firefox" },                                                    "Browser")
  Bind.focus_or_launch("Q",         { program = "qutebrowser", class = "org.qutebrowser.qutebrowser" },                                            "QuteBrowser")
  Bind.focus_or_launch("C",         { program = TERM, title = "Tmux Config",             cmd = TERM .. ' -e tmuxifier load-session config' },      "Tmuxifier Config")
  Bind.focus_or_launch("SHIFT + C", { program = TERM, title = "Tmux Client App", cmd = TERM .. ' -e tmuxifier load-session client-dev' },      "Tmuxifier Client")
  Bind.focus_or_launch("F",         { program = TERM, class = "yazi",                    cmd = TERM .. ' --class yazi -e yazi' },                  "Files")
  Bind.focus_or_launch("SHIFT + F", { program = "dolphin",     class = "org.kde.dolphin" },                                                        "Dolphin")
  Bind.focus_or_launch("M",         { program = "betterbird",  class = "eu.betterbird.Betterbird", cmd = 'flatpak run eu.betterbird.Betterbird' }, "Mail")
  Bind.focus_or_launch("S",         { program = "slack",       class = "Slack" },                                                                  "Slack")
  Bind.focus_or_launch("T",         { program = TERM, exclude_title = "Tmux" },                                                                    "Terminal")
  Bind.focus_or_launch("U",         { program = TERM, title = "Tmux UpHill",             cmd = TERM .. ' -e tmuxifier load-session uphill' },      "Tmuxifier UpHill")
  -- stylua: ignore end

  -- !--- Monitors ---
  for i, entry in ipairs(Config.monitors) do
    local sel = entry.description and ("desc:" .. entry.description) or entry.name
    if sel then
      Bind.exec(tostring(i), function() hl.dispatch(hl.dsp.focus({ monitor = sel })) end, "Monitor " .. i)
    end
  end

  Bind.set_escape(SUBMAP.go)
end)
