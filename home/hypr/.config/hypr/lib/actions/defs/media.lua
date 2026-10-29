-- Actions for the media keys: tracks, volume, mute and brightness. One label per action, so every key bound to one
-- shows the same name. The performers stay in lib/actions/media.lua.
local Act = require("lib.act") ---@class ActionLib

-- Every key bound to these gets the flags: `locked` keeps it working on the lock screen, `repeating` lets volume ride
-- a held key.
local ONESHOT = { submap_universal = true, locked = true }
local REPEATING = { submap_universal = true, locked = true, repeating = true }

--- Run `Media[name]()` on each key press; the performers return a closure.
--- @param name string
--- @return fun()
local function media(name)
  return function() require("lib.actions.media")[name]()() end
end

Act.define("media.prev", {
  label = "Previous Track",
  intent = "Go back to the previous track.",
  opts = ONESHOT,
  run = media("prev"),
})

Act.define("media.next", {
  label = "Next Track",
  intent = "Skip to the next track.",
  opts = ONESHOT,
  run = media("next"),
})

Act.define("media.play_pause", {
  label = "Play/Pause Media",
  intent = "Play the paused player, or pause the playing one.",
  opts = ONESHOT,
  run = media("play_pause"),
})

Act.define("media.volume_up", {
  label = "Volume Up",
  intent = "Raise the volume by 5%, up to 100%.",
  opts = REPEATING,
  run = media("volume_up"),
})

Act.define("media.volume_down", {
  label = "Volume Down",
  intent = "Lower the volume by 5%.",
  opts = REPEATING,
  run = media("volume_down"),
})

Act.define("media.mute", {
  label = "Mute",
  intent = "Mute the speakers, or unmute them.",
  opts = ONESHOT,
  run = media("mute"),
})

Act.define("media.mute_mic", {
  label = "Mute Mic",
  intent = "Mute the microphone, or unmute it.",
  opts = ONESHOT,
  run = media("mute_mic"),
})

Act.define("media.brightness_up", {
  label = "Brightness Up",
  intent = "Raise the screen brightness by 10%.",
  opts = ONESHOT,
  run = media("brightness_up"),
})

Act.define("media.brightness_down", {
  label = "Brightness Down",
  intent = "Lower the screen brightness by 10%.",
  opts = ONESHOT,
  run = media("brightness_down"),
})
