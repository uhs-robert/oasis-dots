-- home/hypr/.config/hypr/theme/generate/init.lua

--- @class Generate
--- @field hyprland fun(c: table) Applies colors to Hyprland via hl.config()
--- @field waybar   fun(c: table) Writes theme-colors.css and restarts waybar + swaync
--- @field rofi     fun(c: table) Writes colors.rasi
--- @field conf     fun(c: table) Writes theme.conf with rgb/rgba variables
--- @field swaync   fun(c: table) Writes theme-colors.css to ~/.config/swaync/
local Generate = {}

Generate.hyprland = require("theme.generate.hyprland")
Generate.waybar = require("theme.generate.waybar")
Generate.rofi = require("theme.generate.rofi")
Generate.conf = require("theme.generate.conf")
Generate.swaync = require("theme.generate.swaync")

--- Runs all generators with the provided color table.
--- @param c table Palette color table from theme.colors.*
Generate.all = function(c)
  Generate.hyprland(c)
  Generate.waybar(c)
  Generate.rofi(c)
  Generate.conf(c)
  Generate.swaync(c)
end

return Generate
