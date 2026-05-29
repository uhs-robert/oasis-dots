--- Applications submap
--- Each bind launches or focuses an app then exits

local Config = require("config") --- @class Config
local Apps = require("lib.actions.apps") --- @class Apps
local Cmd = require("lib.actions.cmd") --- @class Cmd
local Menu = require("lib.actions.menu") --- @class Menu
local Submap = require("lib.key.submap") --- @class Submap

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
    { "SPACE",     Menu.hyprwindow(),                    "Find Window" },
    { "SLASH",     Menu.drun(),                          "Search Applications" },
    { "B",         Apps.open("bottles"),                 "Bottles" },
    { "C",         Apps.open("qalculate-gtk"),           "Calculator" },
    { "D",         Apps.open("deluge"),                  "Deluge" },
    { "SHIFT + D", Cmd.term("aria2tui"),                 "Aria2tui" },
    { "E",         Cmd.term(EDITOR),                     "Editor" },
    { "F",         Apps.open("firefox"),                 "Firefox" },
    { "G",         Apps.open("gimp"),                    "Gimp" },
    { "I",         Apps.open("inkscape"),                "Inkscape" },
    -- { "K",         Apps.open("kate"),                    "Kate" },
    { "M",         Apps.focus_or_launch(APP.betterbird), "Mail" },
    -- { "SHIFT + N", Cmd.term("newsboat"),                  "Newsboat" },
    { "P",         Apps.focus_or_launch(APP.protonplus), "ProtonPlus" },
    { "Q",         Apps.open("qutebrowser"),             "QuteBrowser" },
    { "R",         Apps.focus_or_launch(APP.cliamp),     "Radio (Cliamp)" },
    { "S",         Apps.focus_or_launch(APP.slack),      "Slack" },
    { "SHIFT + S", Apps.focus_or_launch(APP.steam),      "Steam" },
    -- { "V",         Apps.open("code"),                    "VS Code" },
    { "W",         Apps.open("libreoffice --writer"),    "LibreOffice Writer" },
    { "X",         Apps.open("libreoffice --calc"),      "LibreOffice Calc" },
  },
}).setup()
