--- Apply wallpaper to a monitor when it is added.
local function enable_wallpaper_rotation()
  hl.on(
    "monitor.added",
    function(mon) hl.exec_cmd("lua ~/.config/hypr/mods/wallpaper/init.lua --monitor " .. mon.name) end
  )
end

--- Enable all mods. Add calls here to register additional mods.
local function init()
  enable_wallpaper_rotation()
  require("mods.workspace_apps")
end

init()
