--- System submap — entered with SUPER+Q.
--- Each bind runs a system command then exits (oneshot via catchall = "reset").
--- ESCAPE exits without action.
local Config  = require("config")
local Scripts = require("lib.scripts")
local Submap  = require("lib.key.submap")
local Apps    = require("lib.actions.apps")

local TERM   = Config.app.term
local EDITOR = Config.app.editor or "nvim"

local CMD = {
  logout   = 'command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch "hl.dsp.exit()"',
  reboot   = "systemctl reboot",
  poweroff = "systemctl poweroff",
}

return Submap.define({
  name  = "System",
  desc  = "+System",
  enter = Config.leader .. " + Q",

  escape   = "reset",
  catchall = "reset",

  -- stylua: ignore start
  binds = {
    { "SLASH",     Apps.run(TERM .. " -e " .. EDITOR .. " ~/.config/hypr/keymaps/global.lua"),                                                                    "Edit Keybinds" },
    { "SPACE",     Apps.run(TERM .. " -e btop"),                                                                                                                   "Task Manager" },
    { "D",         Apps.run(Config.app.display_manager),                                                                                                           "Display Manager" },
    { "H",         Apps.run("hyprctl reload"),                                                                                                                     "Reload Hyprland" },
    { "SHIFT + H", Apps.run("hyprpm reload -n"),                                                                                                                   "Reload Hyprpm Plugins" },
    { "I",         Apps.run(Scripts.nmtui),                                                                                                                        "Internet (nmtui)" },
    { "K",         Apps.run("hyprctl kill"),                                                                                                                       "Kill App (Click)" },
    { "L",         Apps.run(Scripts.confirm_action .. " --title Lock      --glyph '󰌾' --exec '" .. Scripts.hyprlock .. "'"),                                       "Lock" },
    { "SHIFT + M", Apps.run(Scripts.toggle_mpris_mode),                                                                                                            "Toggle Mpris Mode" },
    { "N",         Apps.run("swaync-client -t -sw"),                                                                                                               "Notification Center" },
    { "E",         Apps.run(Scripts.confirm_action .. " --title Logout    --glyph '󰍃' --exec '" .. CMD.logout .. "'"),                                             "Logout" },
    { "R",         Apps.run(Scripts.confirm_action .. " --title Reboot    --glyph '󰜉' --exec '" .. CMD.reboot .. "'"),                                             "Reboot" },
    { "P",         Apps.run(Scripts.confirm_action .. " --title Power Off --glyph '󰐥' --exec '" .. CMD.poweroff .. "'"),                                           "Power Off" },
    { "T",         Apps.run("~/.config/hypr/theme/switch.lua '" .. Config.app.dmenu_cmd .. "'"),                                                                  "Theme Switch" },
    { "U",         Apps.run(TERM .. " -e sysup"),                                                                                                                  "Update System" },
    { "W",         Apps.run("killall swaync swaync-client waybar; swaync & waybar &"),                                                                             "Restart Waybar" },
    { "SHIFT + W", Apps.run("killall swaync swaync-client waybar; swaync & ~/clones/Waybar/build/waybar -c ~/.config/waybar/config.jsonc -s ~/.config/waybar/style.css &"), "Restart Waybar (Github)" },
  },
  -- stylua: ignore end
})
