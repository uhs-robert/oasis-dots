-- home/hypr/.config/hypr/extensions/init.lua

--- Apply wallpaper to a monitor when it is added.
local function enable_wallpaper_rotation()
  hl.on(
    "monitor.added",
    function(mon) hl.exec_cmd("lua ~/.config/hypr/extensions/wallpaper/init.lua --monitor " .. mon.name) end
  )
end

--- Enable all extensions. Add calls here to register additional extensions.
local function init()
  enable_wallpaper_rotation()
  require("extensions.auto_launcher")
end

init()
