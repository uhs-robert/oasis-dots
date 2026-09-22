-- home/hypr/.config/hypr/theme/generate/quickshell.lua

local HOME = os.getenv("HOME")
local Utils = require("lib.utils") ---@class Utils

local CONFIG_DIR = HOME .. "/.config/quickshell"
local THEME_DIR = CONFIG_DIR .. "/theme"

--- Returns true if path exists (file or directory).
--- @param path string
--- @return boolean
local function exists(path) return os.rename(path, path) ~= nil end

--- Writes theme.json to ~/.config/quickshell/theme/, skipped if quickshell isn't installed.
--- @param c table Palette color table from theme.colors.*
return function(c)
  if not exists(CONFIG_DIR) then return end
  os.execute('mkdir -p "' .. THEME_DIR .. '"')

  local json = string.format(
    [[{
  "bg_core": "%s",
  "bg_mantle": "%s",
  "bg_shadow": "%s",
  "bg_surface": "%s",
  "fg_core": "%s",
  "fg_strong": "%s",
  "fg_muted": "%s",
  "fg_dim": "%s",
  "primary": "%s",
  "secondary": "%s",
  "accent": "%s",
  "yellow": "%s",
  "error": "%s",
  "warning": "%s",
  "info": "%s",
  "hint": "%s",
  "ok": "%s",
  "red": "%s",
  "green": "%s",
  "blue": "%s",
  "cyan": "%s",
  "magenta": "%s"
}
]],
    c.bg_core,
    c.bg_mantle,
    c.bg_shadow,
    c.bg_surface,
    c.fg_core,
    c.fg_strong,
    c.fg_muted,
    c.fg_dim,
    c.theme_primary,
    c.theme_secondary,
    c.theme_accent,
    c.yellow,
    c.error,
    c.warning,
    c.info,
    c.hint,
    c.ok,
    c.red,
    c.green,
    c.blue,
    c.cyan,
    c.magenta
  )

  Utils.write_file(THEME_DIR .. "/theme.json", json)
end
