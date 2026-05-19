--- Media actions: volume, brightness, playerctl.

--- @class MediaActions
local Media = {}

--- @param cmd string shell command to execute via hyprland dispatcher
--- @return fun() deferred action suitable for Bind
local exec = function(cmd)
  return function() hl.dispatch(hl.dsp.exec_cmd(cmd)) end
end

function Media.volume_up() return exec("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+") end
function Media.volume_down() return exec("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-") end
function Media.mute() return exec("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle") end
function Media.mute_mic() return exec("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle") end
function Media.brightness_up() return exec("brightnessctl s 10%+") end
function Media.brightness_down() return exec("brightnessctl s 10%-") end
function Media.play_pause() return exec("playerctl play-pause") end
function Media.next() return exec("playerctl next") end
function Media.prev() return exec("playerctl previous") end

return Media
