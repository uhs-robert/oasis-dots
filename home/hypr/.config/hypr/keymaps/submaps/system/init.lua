--- System submap
--- Each bind runs a system command

local Config = require("config") --- @class Config
local Scripts = require("lib.scripts") --- @class Scripts
local Submap = require("lib.key.submap") --- @class Submap
local Cmd = require("lib.actions.cmd") ---@class Cmd

local TERM_CMD = Config.app.term_cmd
local TUI_FILES = Config.app.tui_file_manager

local CMD = {
  edit_keymaps = TERM_CMD .. " -e " .. TUI_FILES .. " ~/.config/hypr/keymaps/",
  theme_switch = "~/.config/hypr/theme/switch.lua '" .. Config.app.dmenu_cmd .. "'",
  restart_voxtype = "systemctl --user restart voxtype",
}

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
    { "SLASH",     Cmd.run(CMD.edit_keymaps),           "Edit Keymaps" },
    { "SPACE",     Cmd.term("btop"),                    "Task Manager" },
    { "A",         Cmd.term("abtop"),                   "AI Manager" },
    { "D",         Cmd.run(Config.app.display_manager), "Display Manager" },
    { "E",         Cmd.run(POWER.logout),               "Logout" },
    { "H",         Cmd.run("hyprctl reload"),           "Reload Hyprland" },
    { "SHIFT + H", Cmd.run("hyprpm reload -n"),         "Reload Hyprpm Plugins" },
    { "I",         Cmd.run(Scripts.nmtui),              "Internet (nmtui)" },
    { "K",         Cmd.run("hyprctl kill"),             "Kill App (Click)" },
    { "L",         Cmd.run(POWER.lock),                 "Lock" },
    { "SHIFT + L", Cmd.run(Scripts.toggle_autolock),    "Toggle Auto-Lock" },
    { "N",         Cmd.run(Scripts.qs_ipc .. " call popup open notifications"), "Notification Center" },
    { "R",         Cmd.run(POWER.reboot),               "Reboot" },
    { "SHIFT + R", require("config.autostart"),         "Replay Autostart" },
    { "P",         Cmd.run(POWER.off),                  "Power Off" },
    { "T",         Cmd.run(CMD.theme_switch),           "Theme Switch" },
    { "U",         Cmd.term("topgrade"),                "Update System" },
    { "V",         Cmd.term("voxtype configure"),       "Voxtype Settings" },
    { "SHIFT + V", Cmd.term(CMD.restart_voxtype),       "Voxtype Restart" },
    { "X",         Cmd.run("hyprctl seterror disable"), "Disabled Hypr Errors" },
  },
}).setup()
