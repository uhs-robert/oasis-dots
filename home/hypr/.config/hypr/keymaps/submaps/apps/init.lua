--- Applications submap
--- Each bind launches or focuses an app then exits

local Config = require("config") --- @class Config
local Submap = require("lib.key.submap") --- @class Submap

-- The actions the rows name.
require("lib.act.defs.apps")
require("lib.act.defs.launch")
require("lib.act.defs.pickers")

local function focus_app(app) return { "apps.focus", { app } } end
local function open_app(app) return { "apps.open", { app } } end

Submap.define({
  name = "Applications",
  desc = "+Applications",
  enter = Config.leader .. " + A",

  escape = "reset",
  catchall = "reset",

  -- stylua: ignore
  binds = {
    { "SPACE",     "picker.windows" },
    { "SLASH",     "menu.drun",                           "Search Applications" },
    { "B",         open_app("bottles"),                   "Bottles" },
    { "C",         open_app("qalculate"),                 "Calculator" },
    { "D",         open_app("discord"),                   "Discord" },
    { "E",         "terminal.editor" },
    { "F",         open_app("firefox"),                   "Firefox" },
    { "G",         focus_app("steam"),                    "Games (Steam)" },
    { "I",         open_app("gimp"),                      "Image (Gimp)" },
    { "K",         "plans.board" },
    { "M",         focus_app("betterbird"),               "Mail" },
    { "P",         focus_app("protonplus"),               "ProtonPlus" },
    { "Q",         open_app("qutebrowser"),               "QuteBrowser" },
    { "R",         focus_app("cliamp"),                   "Radio (cliamp)" },
    { "S",         focus_app("slack"),                    "Slack" },
    { "T",         open_app("deluge"),                    "Torrent" },
    { "V",         open_app("inkscape"),                  "Vector (Inkscape)" },
    { "W",         open_app("libreoffice_writer"),        "LibreOffice Writer" },
    { "X",         open_app("libreoffice_calc"),          "LibreOffice Calc" },
  },
}).setup()
