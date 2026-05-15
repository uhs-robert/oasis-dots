-- home/hypr/.config/hypr/config/system/keys/submaps/apps.lua

local Config = require("config") --- @class Config
local Bind = require("lib.submap_bind") --- @class SubmapBind
local SUBMAP = require("config.system.keys.submap").map
local Workspaces = require("lib.workspaces") --- @class Workspaces

local MENU = Config.app.menu
local TERM = Config.app.term
local EDITOR = Config.app.editor or "nvim"

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
  Bind.run("E", TERM .. " -e " .. EDITOR, "Editor")
  Bind.run("F", "firefox", "Firefox")
  Bind.run("G", "gimp", "Gimp")
  Bind.run("I", "inkscape", "Inkscape")
  Bind.run("K", "kate", "Kate")
  Bind.focus_or_launch("M", { program = "betterbird", class = email, cmd = "flatpak run " .. email }, "Mail")
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
