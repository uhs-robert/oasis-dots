-- home/hypr/.config/hypr/config/system/keys/submaps/system.lua

local Config = require("config") ---@class Config
local SubBind = require("lib.submap_bind") ---@class SubBind
local Scripts = require("lib.scripts") ---@class Scripts
local SUBMAP = require("config.system.keys.submap").map

local TERM = Config.app.term
local EDITOR = Config.app.editor or "nvim"

local CMD = {
  logout = 'command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch "hl.dsp.exit()"',
  reboot = "systemctl reboot",
  poweroff = "systemctl poweroff",
}

--- System
hl.define_submap(SUBMAP.system.name, function()
  -- !--- Shortcuts ---
  -- stylua: ignore start
  SubBind.run("SLASH",     TERM .. " -e " .. EDITOR .. " ~/.config/hypr/config/system/keys/init.lua",  "Edit Keybinds")
  SubBind.run("SPACE",     TERM .. " -e btop",                                             "Task Manager")
  SubBind.run("I",         Scripts.nmtui,                                                  "Internet Network Manager")
  SubBind.run("SHIFT + M", Scripts.toggle_mpris_mode,                                      "Toggle Waybar Mpris Mode")
  SubBind.run("N",         "swaync-client -t -sw",                                         "Notification Center")
  SubBind.run("U",         TERM .. " -e sysup",                                            "Update System")

  -- !--- Quick reloads ---
  SubBind.run("W",         "killall swaync swaync-client waybar; swaync & waybar &",       "Restart Waybar")
  SubBind.run("SHIFT + W", "killall swaync swaync-client waybar; swaync & ~/clones/Waybar/build/waybar -c ~/.config/waybar/config.jsonc -s ~/.config/waybar/style.css &", "Restart Waybar (Github)")
  SubBind.run("H",         "hyprctl reload",                                               "Reload Hyprland")
  SubBind.run("SHIFT + H", "hyprpm reload -n",                                             "Reload Hyprpm Plugins")
  SubBind.run("T",         "~/.config/hypr/theme/switch.lua '" .. Config.app.dmenu_cmd .. "'", "Theme Switch")
  SubBind.run("D",         Config.app.display_manager,                                     "Display Manager")
  SubBind.run("K",         "hyprctl kill",                                                 "Kill Application (Click)")

  -- !--- With confirmation ---
  SubBind.run("L", Scripts.confirm_action .. " --title Lock --glyph '󰌾' --exec '" .. Scripts.hyprlock .. "'",    "Lock Computer")
  SubBind.run("E", Scripts.confirm_action .. " --title Logout --glyph '󰍃' --exec '" .. CMD.logout .. "'",        "Exit Hyprland")
  SubBind.run("R", Scripts.confirm_action .. " --title Reboot    --glyph '󰜉' --exec '" .. CMD.reboot .. "'",     "Reboot Computer")
  SubBind.run("P", Scripts.confirm_action .. " --title Power\\ Off --glyph '󰐥' --exec '" .. CMD.poweroff .. "'", "Power Off")
  -- stylua: ignore end

  SubBind.bind_exits({ swallow_mispress = true })
end)
