--- System submap
--- Each bind runs a system command

local Config = require("config") --- @class Config
local Scripts = require("lib.scripts") --- @class Scripts
local Submap = require("lib.key.submap") --- @class Submap
local Cmd = require("lib.actions.cmd") ---@class Cmd

local TERM = Config.app.term
local EDITOR = Config.app.editor or "nvim"

local CMD = {
  logout = 'command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch "hl.dsp.exit()"',
  reboot = "systemctl reboot",
  poweroff = "systemctl poweroff",
  restart_waybar = "killall swaync swaync-client waybar; swaync & waybar &",
  restart_waybar_git = "killall swaync swaync-client waybar; swaync & ~/clones/Waybar/build/waybar -c ~/.config/waybar/config.jsonc -s ~/.config/waybar/style.css &",
  edit_keymaps = TERM .. " -e " .. EDITOR .. " ~/.config/hypr/keymaps/global.lua",
  theme_switch = "~/.config/hypr/theme/switch.lua '" .. Config.app.dmenu_cmd .. "'",
}

local POWER = {
  logout = Scripts.confirm_action .. " --title Logout    --glyph '󰍃' --exec '" .. CMD.logout .. "'",
  lock = Scripts.confirm_action .. " --title Lock      --glyph '󰌾' --exec '" .. Scripts.hyprlock .. "'",
  reboot = Scripts.confirm_action .. " --title Reboot    --glyph '󰜉' --exec '" .. CMD.reboot .. "'",
  off = Scripts.confirm_action .. " --title Power Off --glyph '󰐥' --exec '" .. CMD.poweroff .. "'",
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
    { "D",         Cmd.run(Config.app.display_manager), "Display Manager" },
    { "E",         Cmd.run(POWER.logout),               "Logout" },
    { "H",         Cmd.run("hyprctl reload"),           "Reload Hyprland" },
    { "SHIFT + H", Cmd.run("hyprpm reload -n"),         "Reload Hyprpm Plugins" },
    { "I",         Cmd.run(Scripts.nmtui),              "Internet (nmtui)" },
    { "K",         Cmd.run("hyprctl kill"),             "Kill App (Click)" },
    { "L",         Cmd.run(POWER.lock),                 "Lock" },
    { "N",         Cmd.run("swaync-client -t -sw"),     "Notification Center" },
    { "SHIFT + M", Cmd.run(Scripts.toggle_mpris_mode),  "Toggle Mpris Mode" },
    { "R",         Cmd.run(POWER.reboot),               "Reboot" },
    { "P",         Cmd.run(POWER.off),                  "Power Off" },
    { "T",         Cmd.run(CMD.theme_switch),           "Theme Switch" },
    { "U",         Cmd.term("sysup"),                   "Update System" },
    { "W",         Cmd.run(CMD.restart_waybar),         "Restart Waybar" },
    { "SHIFT + W", Cmd.run(CMD.restart_waybar_git),     "Restart Waybar (Github)" },
  },
}).setup()
