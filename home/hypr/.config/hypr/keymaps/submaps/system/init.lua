--- System submap
--- Each bind runs a system command or a command-line tool

local Config = require("config") --- @class Config
local Submap = require("lib.key.submap") --- @class Submap

-- The actions the rows name.
require("lib.actions.defs.apps")
require("lib.actions.defs.launch")
require("lib.actions.defs.power")
require("lib.actions.defs.system")

local function tool(name) return { "terminal.tool", { name } } end

Submap.define({
  name = "System",
  desc = "+System",
  enter = Config.leader .. " + Q",

  escape = "reset",
  catchall = "reset",

  -- stylua: ignore start
  binds = {
    { "SLASH",     "system.edit_keymaps" },
    { "SPACE",     "terminal.task_manager" },
    { "A",         { "terminal.tool", { "abtop" } },    "AI Manager" },
    { "SHIFT + A", tool("aria2tui"),                    "Aria2tui" },
    { "B",         "system.restart_bar" },
    { "C",         tool("qalc"),                        "Calculate (qalc)" },
    { "D",         tool("doggo"),                       "DNS (doggo)" },
    { "E",         { "power.confirm", { "logout" } }, "Logout" },
    { "G",         tool("gping"),                       "Ping (gping)" },
    { "H",         "system.reload_hyprland" },
    { "SHIFT + H", "system.reload_plugins" },
    { "J",         tool("lazyjournal"),                 "Journal (lazyjournal)" },
    { "K",         "system.kill_app" },
    { "L",         { "power.confirm", { "lock" } }, "Lock" },
    { "SHIFT + L", "system.toggle_autolock" },
    { "R",         { "power.confirm", { "reboot" } }, "Reboot" },
    { "SHIFT + R", "system.replay_autostart" },
    { "P",         { "power.confirm", { "poweroff" } }, "Power Off" },
    { "U",         tool("gdu"),                         "Disk Usage (gdu)" },
    { "V",         "system.voxtype_settings" },
    { "SHIFT + V", "system.voxtype_restart" },
    { "W",         tool("xh"),                          "HTTP (xh)" },
    { "X",         "system.disable_errors" },
  },
}).setup()
