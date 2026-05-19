--- Media actions: volume, brightness, playerctl.

local Hypr = require("lib.hypr") --- @class HyprLib

--- @class MediaActions
local Media = {}

function Media.volume_up() return Hypr.exec("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+") end
function Media.volume_down() return Hypr.exec("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-") end
function Media.mute() return Hypr.exec("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle") end
function Media.mute_mic() return Hypr.exec("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle") end
function Media.brightness_up() return Hypr.exec("brightnessctl s 10%+") end
function Media.brightness_down() return Hypr.exec("brightnessctl s 10%-") end
function Media.play_pause() return Hypr.exec("playerctl play-pause") end
function Media.next() return Hypr.exec("playerctl next") end
function Media.prev() return Hypr.exec("playerctl previous") end

return Media
