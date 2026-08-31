-- home/hypr/.config/hypr/theme/init.lua

local Config = require("config") ---@class Config
local Generate = require("theme.generate") ---@class Generate

-- Restore last theme selected via switch.lua if the state file exists.
local state = io.open(os.getenv("HOME") .. "/.config/hypr/theme/.current_theme", "r")
if state then
  local saved = state:read("*line")
  state:close()
  if saved and saved ~= "" then Config.theme = saved end
end

--- @class Theme
--- @field colors table Cached palette color table for the active theme
--- @field load fun(): table Loads palette for Config.theme into Theme.colors
--- @field apply fun() Runs all generators against the active palette
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
