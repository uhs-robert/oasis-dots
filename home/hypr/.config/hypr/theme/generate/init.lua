-- home/hypr/.config/hypr/theme/generate/init.lua

--- @class Generate
--- @field hyprland  fun(c: table) Applies colors to Hyprland via hl.config()
--- @field rofi      fun(c: table) Writes colors.rasi
--- @field conf      fun(c: table) Writes theme.conf with rgb/rgba variables
--- @field terminals fun(c: table) Updates Ghostty/Kitty/Foot theme configs
--- @field quickshell fun(c: table) Writes theme.json to ~/.config/quickshell/theme/
local Generate = {}

Generate.hyprland = require("theme.generate.hyprland")
Generate.rofi = require("theme.generate.rofi")
Generate.conf = require("theme.generate.conf")
Generate.terminals = require("theme.generate.terminals")
Generate.quickshell = require("theme.generate.quickshell")

--- Runs all generators with the provided color table.
--- @param c table Palette color table from theme.colors.*
Generate.all = function(c)
  Generate.hyprland(c)
  Generate.rofi(c)
  Generate.conf(c)
  Generate.terminals(c)
  Generate.quickshell(c)
end

return Generate
