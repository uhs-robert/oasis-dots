-- home/hypr/.config/hypr/extensions/init.lua

--- Apply wallpaper to a monitor when it is added.
local function enable_wallpaper_rotation()
  hl.on(
    "monitor.added",
    function(mon) hl.exec_cmd("lua ~/.config/hypr/extensions/wallpaper/init.lua --monitor " .. mon.name) end
  )
end

--- Sync the rofi Steam entry with the Steam launch command once per session start.
local function sync_steam_desktop_entry()
  hl.on("hyprland.start", function() require("extensions.steam").sync(require("lib.actions.apps").steam_prime) end)
end

--- Enable all extensions. Add calls here to register additional extensions.
local function init()
  enable_wallpaper_rotation()
  sync_steam_desktop_entry()
  require("extensions.auto_launcher")
end

init()
