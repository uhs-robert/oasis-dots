-- home/hypr/.config/hypr/theme/generate/quickshell.lua

local HOME = os.getenv("HOME")
local Utils = require("lib.utils") ---@class Utils

local CONFIG_DIR = HOME .. "/.config/quickshell"
local THEME_DIR = CONFIG_DIR .. "/theme"

--- Returns true if path exists (file or directory).
--- @param path string
--- @return boolean
local function exists(path) return os.rename(path, path) ~= nil end

--- Escape string for JSON (backslash and quote).
local function escape_json(s) return s:gsub("\\", "\\\\"):gsub('"', '\\"') end

--- Writes theme.json to ~/.config/quickshell/theme/, skipped if quickshell isn't installed.
--- @param c table Palette color table from theme.colors.*
return function(c)
  if not exists(CONFIG_DIR) then return end
  os.execute('mkdir -p "' .. THEME_DIR .. '"')

  local keys = {}
  for k in pairs(c) do
    if type(k) == "string" and type(c[k]) == "string" and not k:match("^color%d+$") then table.insert(keys, k) end
  end
  table.sort(keys)

  local lines = { "{" }
  for i, k in ipairs(keys) do
    local v = escape_json(c[k])
    local line = string.format('  "%s": "%s"', k, v)
    if i < #keys then line = line .. "," end
    table.insert(lines, line)
  end
  table.insert(lines, "}")

  Utils.write_file(THEME_DIR .. "/theme.json", table.concat(lines, "\n"))
end
