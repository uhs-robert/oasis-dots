-- home/hypr/.config/hypr/config/system/keys/submaps/apps.lua

local Config = require("config") --- @class Config
local SubBind = require("lib.submap_bind") --- @class SubBind
local SUBMAP = require("config.system.keys.submap").map
local Workspaces = require("lib.workspaces") --- @class Workspaces

local MENU = Config.app.menu
local TERM = Config.app.term
local EDITOR = Config.app.editor or "nvim"

--- Applications
hl.define_submap(SUBMAP.applications.name, function()
  local email = "eu.betterbird.Betterbird"

  -- !--- Shortcuts ---
  SubBind.run("SPACE", MENU .. " -i -show hyprwindow", "Find window by name")
  SubBind.run("SLASH", MENU .. " -i -show drun", "Search applications")

  -- !--- Apps ---
  SubBind.run("B", "bottles", "Bottles")
  SubBind.run("C", "qalculate-gtk", "Calculator")
  SubBind.run("D", "deluge", "Deluge")
  SubBind.run("SHIFT + D", TERM .. " -e aria2tui", "Aria2tui")
  SubBind.run("E", TERM .. " -e " .. EDITOR, "Editor")
  SubBind.run("F", "firefox", "Firefox")
  SubBind.run("G", "gimp", "Gimp")
  SubBind.run("I", "inkscape", "Inkscape")
  SubBind.run("K", "kate", "Kate")
  SubBind.focus_or_launch("M", { program = "betterbird", class = email, cmd = "flatpak run " .. email }, "Mail")
  SubBind.run("SHIFT + N", TERM .. " -e newsboat", "Newsboat")
  SubBind.run("P", "flatpak run com.vysp3r.ProtonPlus", "ProtonPlus")
  SubBind.run("Q", "qutebrowser", "QuteBrowser")
  SubBind.focus_or_launch("R", { program = "cliamp", title = "cliamp", cmd = TERM .. " -e cliamp" }, "Radio (Cliamp)")
  SubBind.run("SHIFT + S", "steam", "Steam")
  SubBind.focus_or_launch("S", { program = "slack", class = "Slack" }, "Slack")
  SubBind.run("V", "code", "VS Code")
  SubBind.run("W", "libreoffice --writer", "LibreOffice Writer")
  SubBind.run("X", "libreoffice --calc", "LibreOffice Calc")

  SubBind.bind_exits({ swallow_mispress = true })
  hl.bind("Escape", hl.dsp.submap("reset"))
end)
