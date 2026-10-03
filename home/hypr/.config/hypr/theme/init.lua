-- home/hypr/.config/hypr/theme/init.lua

local Config = require("config") ---@class Config
local Generate = require("theme.generate") ---@class Generate
local MissingRepos = require("lib.missing_repos") ---@class MissingRepos

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

local on_fallback = false

--- Loads the palette for Config.theme, or the embedded fallback, into Theme.colors.
--- @return table colors Palette color table
Theme.load = function()
  local name = "theme.colors." .. Config.theme
  on_fallback = not package.searchpath(name, package.path)
  if not on_fallback then
    Theme.colors = require(name)
    return Theme.colors
  end
  if package.searchpath("theme.colors.oasis_moonlight", package.path) then
    MissingRepos.add("palette " .. Config.theme .. " not found")
  else
    MissingRepos.add("theme palettes (repos/oasis.nvim)")
  end
  Theme.colors = require("theme.fallback")
  return Theme.colors
end

--- Runs generators against the active palette (Hyprland only on fallback), reloading affected services.
Theme.apply = function()
  local c = Theme.colors or Theme.load()
  if on_fallback then
    Generate.hyprland(c)
  else
    Generate.all(c)
  end
end

Theme.load()
Theme.apply()

return Theme
