local Bind = require("lib.key.bind")
local Media = require("lib.actions.media")

-- stylua: ignore start
Bind.key("XF86AudioRaiseVolume",  Media.volume_up(),     "Volume Up",       { repeating = true, locked = true, submap_universal = true })
Bind.key("XF86AudioLowerVolume",  Media.volume_down(),   "Volume Down",     { repeating = true, locked = true, submap_universal = true })
Bind.key("XF86AudioMute",         Media.mute(),          "Mute",            { locked = true, submap_universal = true })
Bind.key("XF86AudioMicMute",      Media.mute_mic(),      "Mute Mic",        { locked = true, submap_universal = true })
Bind.key("XF86MonBrightnessUp",   Media.brightness_up(), "Brightness Up",   { repeating = true, locked = true, submap_universal = true })
Bind.key("XF86MonBrightnessDown", Media.brightness_down(), "Brightness Down", { repeating = true, locked = true, submap_universal = true })

local pctl = { submap_universal = true, locked = true }
local vol  = { repeating = true, submap_universal = true, locked = true }
Bind.leader_key("ALT + H",     Media.prev(),        "Previous Track",   pctl)
Bind.leader_key("ALT + L",     Media.next(),        "Next Track",       pctl)
Bind.leader_key("ALT + J",     Media.volume_down(), "Volume Down",      vol)
Bind.leader_key("ALT + K",     Media.volume_up(),   "Volume Up",        vol)
Bind.leader_key("ALT + SPACE", Media.play_pause(),  "Play/Pause Media", pctl)

Bind.key("XF86AudioNext",  Media.next(),       "Next Track",   { locked = true, submap_universal = true })
Bind.key("XF86AudioPause", Media.play_pause(), "Pause Media",  { locked = true, submap_universal = true })
Bind.key("XF86AudioPlay",  Media.play_pause(), "Play Media",   { locked = true, submap_universal = true })
Bind.key("XF86AudioPrev",  Media.prev(),       "Prev Track",   { locked = true, submap_universal = true })
