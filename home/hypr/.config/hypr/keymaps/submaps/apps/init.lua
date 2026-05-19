--- Applications submap
--- Each bind launches or focuses an app then exits

local Config = require("config") --- @class Config
local Apps = require("lib.actions.apps") --- @class Apps
local Scripts = require("lib.scripts") --- @class Scripts
local Submap = require("lib.key.submap") --- @class Submap

local MENU = Config.app.menu
local TERM = Config.app.term
local EDITOR = Config.app.editor or "nvim"
local APP = Apps.map

Submap.define({
  name = "Applications",
  desc = "+Applications",
  enter = Config.leader .. " + A",

  escape = "reset",
  catchall = "reset",

  -- stylua: ignore
  binds = {
    { "SPACE",     Apps.open(MENU .. " -i -show hyprwindow"),       "Find Window" },
    { "SLASH",     Apps.open(MENU .. " -i -show drun"),             "Search Applications" },
    { "B",         Apps.open("bottles"),                            "Bottles" },
    { "C",         Apps.open("qalculate-gtk"),                      "Calculator" },
    { "D",         Apps.open("deluge"),                             "Deluge" },
    { "SHIFT + D", Apps.open(TERM .. " -e aria2tui"),               "Aria2tui" },
    { "E",         Apps.open(TERM .. " -e " .. EDITOR),             "Editor" },
    { "F",         Apps.open("firefox"),                            "Firefox" },
    { "G",         Apps.open("gimp"),                               "Gimp" },
    { "I",         Apps.open("inkscape"),                           "Inkscape" },
    { "K",         Apps.open("kate"),                               "Kate" },
    { "M",         Apps.focus_or_launch(APP.betterbird),            "Mail" },
    { "SHIFT + N", Apps.open(TERM .. " -e newsboat"),               "Newsboat" },
    { "P",         Apps.open("flatpak run com.vysp3r.ProtonPlus"),  "ProtonPlus" },
    { "Q",         Apps.open("qutebrowser"),                        "QuteBrowser" },
    { "R",         Apps.focus_or_launch(APP.cliamp),                "Radio (Cliamp)" },
    { "S",         Apps.focus_or_launch(APP.slack),                 "Slack" },
    { "SHIFT + S", Apps.open("steam"),                              "Steam" },
    { "V",         Apps.open("code"),                               "VS Code" },
    { "W",         Apps.open("libreoffice --writer"),               "LibreOffice Writer" },
    { "X",         Apps.open("libreoffice --calc"),                 "LibreOffice Calc" },
  },
}).setup()
