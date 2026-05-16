--- Applications submap — entered with SUPER+A.
--- Each bind launches or focuses an app then exits (oneshot via catchall = "reset").
--- ESCAPE exits without action.
--- @see modes.apps.actions
local Config = require("config")
local Apps   = require("lib.actions.apps")
local Submap = require("lib.key.submap")

local MENU   = Config.app.menu
local TERM   = Config.app.term
local EDITOR = Config.app.editor or "nvim"

return Submap.define({
  name  = "Applications",
  desc  = "+Applications",
  enter = Config.leader .. " + A",

  escape   = "reset",
  catchall = "reset",

  binds = {
    { "SPACE",       Apps.run(MENU .. " -i -show hyprwindow"),                                               "Find Window" },
    { "SLASH",       Apps.run(MENU .. " -i -show drun"),                                                     "Search Applications" },

    { "B",           Apps.run("bottles"),                                                                     "Bottles" },
    { "C",           Apps.run("qalculate-gtk"),                                                               "Calculator" },
    { "D",           Apps.run("deluge"),                                                                      "Deluge" },
    { "SHIFT + D",   Apps.run(TERM .. " -e aria2tui"),                                                       "Aria2tui" },
    { "E",           Apps.run(TERM .. " -e " .. EDITOR),                                                     "Editor" },
    { "F",           Apps.run("firefox"),                                                                     "Firefox" },
    { "G",           Apps.run("gimp"),                                                                        "Gimp" },
    { "I",           Apps.run("inkscape"),                                                                    "Inkscape" },
    { "K",           Apps.run("kate"),                                                                        "Kate" },
    { "M",           Apps.focus_or_launch({ program = "betterbird", class = "eu.betterbird.Betterbird",
                       cmd = "flatpak run eu.betterbird.Betterbird" }),                                       "Mail" },
    { "SHIFT + N",   Apps.run(TERM .. " -e newsboat"),                                                       "Newsboat" },
    { "P",           Apps.run("flatpak run com.vysp3r.ProtonPlus"),                                          "ProtonPlus" },
    { "Q",           Apps.run("qutebrowser"),                                                                 "QuteBrowser" },
    { "R",           Apps.focus_or_launch({ program = "cliamp", title = "cliamp",
                       cmd = TERM .. " -e cliamp" }),                                                         "Radio (Cliamp)" },
    { "S",           Apps.focus_or_launch({ program = "slack", class = "Slack" }),                           "Slack" },
    { "SHIFT + S",   Apps.run("steam"),                                                                       "Steam" },
    { "V",           Apps.run("code"),                                                                        "VS Code" },
    { "W",           Apps.run("libreoffice --writer"),                                                        "LibreOffice Writer" },
    { "X",           Apps.run("libreoffice --calc"),                                                          "LibreOffice Calc" },
  },
})
