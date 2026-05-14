-- home/hypr/.config/hypr/theme/init.lua

local Config = require("config")
local Generate = require("theme.generate")

--- @class Theme
--- @field colors table Cached palette color table for the active theme
local Theme = {}

--- Loads the palette for Config.theme and caches it in Theme.colors.
--- @return table colors Palette color table
Theme.load = function()
  Theme.colors = require("theme.colors." .. Config.theme)
  return Theme.colors
end

--- Runs all generators against the active palette, reloading affected services.
Theme.apply = function()
  local c = Theme.colors or Theme.load()
  Generate.all(c)
end

Theme.load()
Theme.apply()

return Theme
