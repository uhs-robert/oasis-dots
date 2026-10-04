-- home/hypr/.config/hypr/theme/init.lua

local Config = require("config") ---@class Config
local Generate = require("theme.generate") ---@class Generate
local MissingRepos = require("lib.missing_repos") ---@class MissingRepos

--- @param path string
--- @return string|nil
local function read_saved(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local saved = f:read("*line")
  f:close()
  return (saved and saved ~= "") and saved or nil
end

-- Restore the theme last selected via switch.lua; always write the file so Quickshell can watch it.
local state_dir = require("lib.state")()
local state_file = state_dir .. "/theme"
local saved = read_saved(state_file)
if saved then
  Config.theme = saved
else
  saved = read_saved(os.getenv("HOME") .. "/.config/hypr/theme/.current_theme")
  if saved then Config.theme = saved end
  os.execute("mkdir -p '" .. state_dir .. "'")
  local out = io.open(state_file, "w")
  if out then
    out:write(Config.theme)
    out:close()
  end
end

--- @class Theme
--- @field colors table Cached palette color table for the active theme
--- @field load fun(): table Loads palette for Config.theme into Theme.colors
--- @field apply fun() Runs all generators against the active palette
local Theme = {}

--- Loads the palette for Config.theme, or the embedded fallback, into Theme.colors.
--- @return table colors Palette color table
Theme.load = function()
  local name = "theme.colors." .. Config.theme
  if package.searchpath(name, package.path) then
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

--- Runs generators against the active palette, reloading affected services.
Theme.apply = function() Generate.all(Theme.colors or Theme.load()) end

Theme.load()
Theme.apply()

return Theme
