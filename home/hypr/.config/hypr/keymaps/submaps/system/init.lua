--- System submap
--- Each bind runs a system command

local Config = require("config") --- @class Config
local Submap = require("lib.key.submap") --- @class Submap

-- The actions the rows name.
require("lib.actions.defs.apps")
require("lib.actions.defs.popups")
require("lib.actions.defs.power")
require("lib.actions.defs.system")

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
    { "B",         "system.restart_bar" },
    { "D",         "system.display_manager" },
    { "E",         { "power.confirm", { "logout" } }, "Logout" },
    { "H",         "system.reload_hyprland" },
    { "SHIFT + H", "system.reload_plugins" },
    { "I",         "system.network" },
    { "K",         "system.kill_app" },
    { "L",         { "power.confirm", { "lock" } }, "Lock" },
    { "SHIFT + L", "system.toggle_autolock" },
    { "N",         { "popup.open", { "notifications" } }, "Notification Center" },
    { "R",         { "power.confirm", { "reboot" } }, "Reboot" },
    { "SHIFT + R", "system.replay_autostart" },
    { "P",         { "power.confirm", { "poweroff" } }, "Power Off" },
    { "T",         "system.theme_switch" },
    { "U",         "system.update" },
    { "V",         "system.voxtype_settings" },
    { "SHIFT + V", "system.voxtype_restart" },
    { "W",         "system.next_wallpaper" },
    { "X",         "system.disable_errors" },
  },
}).setup()
