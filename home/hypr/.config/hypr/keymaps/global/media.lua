local Bind = require("lib.key.bind")
local Media = require("lib.actions.media")
-- stylua: ignore start

local OPTS = {
  oneshot = { submap_universal = true, locked = true },
  repeating = { repeating = true, submap_universal = true, locked = true }
}

-- Vim Binds
Bind.leader_key("ALT + H",     Media.prev(),        "Previous Track",   OPTS.oneshot)
Bind.leader_key("ALT + J",     Media.volume_down(), "Volume Down",      OPTS.repeating)
Bind.leader_key("ALT + K",     Media.volume_up(),   "Volume Up",        OPTS.repeating)
Bind.leader_key("ALT + L",     Media.next(),        "Next Track",       OPTS.oneshot)
Bind.leader_key("ALT + SPACE", Media.play_pause(),  "Play/Pause Media", OPTS.oneshot)

-- Keyboard Binds
Bind.key("XF86AudioRaiseVolume",  Media.volume_up(),       "Volume Up",       OPTS.repeating)
Bind.key("XF86AudioLowerVolume",  Media.volume_down(),     "Volume Down",     OPTS.repeating)
Bind.key("XF86AudioMute",         Media.mute(),            "Mute",            OPTS.oneshot)
Bind.key("XF86AudioMicMute",      Media.mute_mic(),        "Mute Mic",        OPTS.oneshot)
Bind.key("XF86AudioNext",         Media.next(),            "Next Track",      OPTS.oneshot)
Bind.key("XF86AudioPause",        Media.play_pause(),      "Pause Media",     OPTS.oneshot)
Bind.key("XF86AudioPlay",         Media.play_pause(),      "Play Media",      OPTS.oneshot)
Bind.key("XF86AudioPrev",         Media.prev(),            "Prev Track",      OPTS.oneshot)
Bind.key("XF86MonBrightnessUp",   Media.brightness_up(),   "Brightness Up",   OPTS.oneshot)
Bind.key("XF86MonBrightnessDown", Media.brightness_down(), "Brightness Down", OPTS.oneshot)
