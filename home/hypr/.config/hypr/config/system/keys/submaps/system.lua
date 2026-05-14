-- home/hypr/.config/hypr/keys/submaps/system.lua

local Config = require("config")
local Bind = require("lib.submap_bind")
local SUBMAP = require("config.system.keys.submap").map

local TERM = Config.app.term

--- System
hl.define_submap(SUBMAP.system.name, function()
  local CONFIRM = "~/.config/waybar/scripts/confirm-action.sh"

    -- !--- Shortcuts ---
    -- stylua: ignore start
    Bind.run("SLASH",     TERM .. " -e nvim ~/.config/hypr/config/keys.conf",          "Edit Keybinds")
    Bind.run("SPACE",     TERM .. " -e btop",                                             "Task Manager")
    Bind.run("M",         "~/.config/hypr/monitors/scripts/toggle-monitor-layout.sh",     "Monitor Layout")
    Bind.run("I",         "~/.config/hypr/scripts/nmtui.sh",                              "Internet Network Manager")
    Bind.run("SHIFT + M", "~/.config/waybar/scripts/toggle_mpris_mode.rb",                "Toggle Waybar Mpris Mode")
    Bind.run("N",         "swaync-client -t -sw",                                         "Notification Center")
    Bind.run("U",         TERM .. " -e sysup",                                            "Update System")

    -- !--- Quick reloads ---
    Bind.run("W",         "killall swaync swaync-client waybar; swaync & waybar &",       "Restart Waybar")
    Bind.run("SHIFT + W", "killall swaync swaync-client waybar; swaync & ~/clones/Waybar/build/waybar -c ~/.config/waybar/config.jsonc -s ~/.config/waybar/style.css &", "Restart Waybar (Github)")
    Bind.run("H",         "hyprctl reload",                                               "Reload Hyprland")
    Bind.run("SHIFT + H", "hyprpm reload -n",                                             "Reload Hyprpm Plugins")
    Bind.run("T",         "~/.config/hypr/theme/main.lua --menu",                         "Theme Switch")
    -- Bind.run("D",      "$DISPLAY_MANAGER",                                             "Display Manager") -- TODO: port $DISPLAY_MANAGER
    Bind.run("K",         "hyprctl kill",                                                 "Kill Application (Click)")

    -- !--- With confirmation ---
    Bind.run("L", CONFIRM .. " --title Lock      --glyph '󰌾' --exec '~/.config/hypr/lua/hyprlock-shot.lua'", "Lock Computer")
    Bind.run(
      "E",
      CONFIRM .. [[ --title Logout --glyph '󰍃' --exec 'command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch "hl.dsp.exit()"' ]],
      "Exit Hyprland"
    )
    Bind.run("R", CONFIRM .. " --title Reboot    --glyph '󰜉' --exec 'systemctl reboot'",                       "Reboot Computer")
    Bind.run("P", CONFIRM .. " --title Power\\ Off --glyph '󰐥' --exec 'systemctl poweroff'",                   "Power Off")
  -- stylua: ignore end

  -- !--- Switch to other submaps ---
  Bind.bind(SUBMAP.cursor, SUBMAP.cursor.fn)

  Bind.set_escape(SUBMAP.system)
end)
