--- Media actions: volume, brightness, playerctl.

local Config = require("config") --- @class Config
local Hypr = require("lib.hypr") --- @class HyprLib

--- Runs brightnessctl, then has Quickshell re-read the backlight for its OSD.
--- @param step string
--- @return fun()
local function brightness(step)
  local refresh = Config.shell == "quickshell" and " ; qs ipc call brightness refresh" or ""
  return Hypr.exec("brightnessctl s " .. step .. refresh)
end

--- @class MediaActions
local Media = {
  volume_up = function() return Hypr.exec("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+") end,
  volume_down = function() return Hypr.exec("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-") end,
  mute = function() return Hypr.exec("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle") end,
  mute_mic = function() return Hypr.exec("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle") end,
  brightness_up = function() return brightness("10%+") end,
  brightness_down = function() return brightness("10%-") end,
  play_pause = function() return Hypr.exec("playerctl play-pause") end,
  next = function() return Hypr.exec("playerctl next") end,
  prev = function() return Hypr.exec("playerctl previous") end,
}

return Media
