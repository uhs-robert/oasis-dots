local Act = require("lib.act") ---@class ActionLib

-- The flags (locked, repeating, submap_universal) come with each action, so a key added here gets them too.
require("lib.act.defs.media")

Act.bind("media.prev", { key = { key = "ALT + H", leader = true } })
Act.bind("media.prev", { key = "XF86AudioPrev" })
Act.bind("media.next", { key = { key = "ALT + L", leader = true } })
Act.bind("media.next", { key = "XF86AudioNext" })
Act.bind("media.play_pause", { key = { key = "ALT + SPACE", leader = true } })
Act.bind("media.play_pause", { key = "XF86AudioPlay" })
Act.bind("media.play_pause", { key = "XF86AudioPause" })
Act.bind("media.volume_up", { key = { key = "ALT + K", leader = true } })
Act.bind("media.volume_up", { key = "XF86AudioRaiseVolume" })
Act.bind("media.volume_down", { key = { key = "ALT + J", leader = true } })
Act.bind("media.volume_down", { key = "XF86AudioLowerVolume" })
Act.bind("media.mute", { key = { key = "ALT + M", leader = true } })
Act.bind("media.mute", { key = "XF86AudioMute" })
Act.bind("media.mute_mic", { key = "XF86AudioMicMute" })
Act.bind("media.brightness_up", { key = "XF86MonBrightnessUp" })
Act.bind("media.brightness_down", { key = "XF86MonBrightnessDown" })
