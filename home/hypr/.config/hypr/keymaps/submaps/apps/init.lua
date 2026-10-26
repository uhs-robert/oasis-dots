--- Applications submap
--- Each bind launches or focuses an app then exits

local Config = require("config") --- @class Config
local Submap = require("lib.key.submap") --- @class Submap

-- The actions the rows name.
require("lib.actions.defs.apps")

local function focus_app(app) return { "apps.focus", { app } } end
local function open_app(app) return { "apps.open", { app } } end
local function tool(name) return { "terminal.tool", { name } } end

Submap.define({
  name = "Applications",
  desc = "+Applications",
  enter = Config.leader .. " + A",

  escape = "reset",
  catchall = "reset",

  -- stylua: ignore
  binds = {
    { "SPACE",     "overview.search",                     "Search Windows" },
    { "SLASH",     "menu.drun",                           "Search Applications" },
    { "A",         tool("aria2tui"),                      "Aria2tui" },
    { "B",         open_app("bottles"),                   "Bottles" },
    { "C",         tool("qalc"),                          "Calculate (qalc)" },
    { "SHIFT + C", open_app("qalculate"),                 "Calculator" },
    { "D",         open_app("discord"),                   "Discord" },
    { "SHIFT + D", tool("doggo"),                         "DNS (doggo)" },
    { "E",         "terminal.editor" },
    { "F",         open_app("firefox"),                   "Firefox" },
    { "G",         open_app("gimp"),                      "Gimp" },
    { "H",         tool("xh"),                            "HTTP (xh)" },
    { "I",         open_app("inkscape"),                  "Inkscape" },
    { "J",         tool("lazyjournal"),                   "Journal (lazyjournal)" },
    -- { "K",         open_app("kate"),                   "Kate" },
    { "M",         focus_app("betterbird"),               "Mail" },
    -- { "SHIFT + N", Cmd.term("newsboat"),               "Newsboat" },
    { "P",         focus_app("protonplus"),               "ProtonPlus" },
    { "SHIFT + P", tool("gping"),                         "Ping (gping)" },
    { "Q",         open_app("qutebrowser"),               "QuteBrowser" },
    { "R",         focus_app("cliamp"),                   "Radio (cliamp)" },
    { "S",         focus_app("slack"),                    "Slack" },
    { "SHIFT + S", focus_app("steam"),                    "Steam" },
    { "T",         open_app("deluge"),                    "Torrent" },
    { "U",         tool("gdu"),                           "Disk Diagnosis (gdu)" },
    -- { "V",         open_app("code"),                   "VS Code" },
    { "W",         open_app("libreoffice_writer"),        "LibreOffice Writer" },
    { "X",         open_app("libreoffice_calc"),          "LibreOffice Calc" },
  },
}).setup()
