--- System submap
--- Each bind runs a system command

local Config = require("config") --- @class Config
local Scripts = require("lib.scripts") --- @class Scripts
local Submap = require("lib.key.submap") --- @class Submap
local Cmd = require("lib.actions.cmd") ---@class Cmd

-- The actions the rows name.
require("lib.actions.defs.apps")
require("lib.actions.defs.popups")
require("lib.actions.defs.system")

-- Not actions yet: the power rows wait for their own.
local POWER = {
  logout = Scripts.qs_ipc .. " call power confirm logout",
  lock = Scripts.qs_ipc .. " call power confirm lock",
  reboot = Scripts.qs_ipc .. " call power confirm reboot",
  off = Scripts.qs_ipc .. " call power confirm poweroff",
}

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
    { "E",         Cmd.run(POWER.logout),               "Logout" },
    { "H",         "system.reload_hyprland" },
    { "SHIFT + H", "system.reload_plugins" },
    { "I",         "system.network" },
    { "K",         "system.kill_app" },
    { "L",         Cmd.run(POWER.lock),                 "Lock" },
    { "SHIFT + L", "system.toggle_autolock" },
    { "N",         { "popup.open", { "notifications" } }, "Notification Center" },
    { "R",         Cmd.run(POWER.reboot),               "Reboot" },
    { "SHIFT + R", "system.replay_autostart" },
    { "P",         Cmd.run(POWER.off),                  "Power Off" },
    { "T",         "system.theme_switch" },
    { "U",         "system.update" },
    { "V",         "system.voxtype_settings" },
    { "SHIFT + V", "system.voxtype_restart" },
    { "W",         "system.next_wallpaper" },
    { "X",         "system.disable_errors" },
  },
}).setup()
