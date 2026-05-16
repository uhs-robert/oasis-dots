--- Media actions: volume, brightness, playerctl.

--- @class MediaActions
local Media = {}

--- @return fun()
function Media.volume_up()
  return function() hl.dispatch(hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+")) end
end

--- @return fun()
function Media.volume_down()
  return function() hl.dispatch(hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-")) end
end

--- @return fun()
function Media.mute()
  return function() hl.dispatch(hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle")) end
end

--- @return fun()
function Media.mute_mic()
  return function() hl.dispatch(hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle")) end
end

--- @return fun()
function Media.brightness_up()
  return function() hl.dispatch(hl.dsp.exec_cmd("brightnessctl s 10%+")) end
end

--- @return fun()
function Media.brightness_down()
  return function() hl.dispatch(hl.dsp.exec_cmd("brightnessctl s 10%-")) end
end

--- @return fun()
function Media.play_pause()
  return function() hl.dispatch(hl.dsp.exec_cmd("playerctl play-pause")) end
end

--- @return fun()
function Media.next()
  return function() hl.dispatch(hl.dsp.exec_cmd("playerctl next")) end
end

--- @return fun()
function Media.prev()
  return function() hl.dispatch(hl.dsp.exec_cmd("playerctl previous")) end
end

return Media
