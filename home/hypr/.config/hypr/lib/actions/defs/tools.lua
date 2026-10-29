-- Actions for the tool keys: zoom, screenshot, voice, passwords and the overviews. Kept apart from
-- keymaps/global/tools.lua, which binds them, so a headless load needs only `lib.act`, not Menu or Config.
local Act = require("lib.act") ---@class ActionLib
local Ipc, Cmd = Act.Ipc, Act.Cmd

local screenshot = "~/.config/hypr/scripts/screenshot.sh"
local voxcmd = "~/.local/bin/voxcmd"

Act.define("screenshot.take", {
  label = "Screenshot",
  intent = "Open the screenshot and recording menu.",
  run = Cmd(screenshot),
})

Act.define("screenshot.pixel", {
  label = "Color Picker",
  intent = "Pick a color from the screen and copy it.",
  run = Cmd(screenshot, "--pixel"),
})

Act.define("zoom.toggle", {
  label = "Zoom",
  intent = "Start the screen magnifier, or stop it when it is running.",
  run = Ipc("zoom", "toggle"),
})

-- While voxtype records, either key stops it and the recording's own mode handles the result.
-- Stop Voice ends everything instead.
Act.define("voice.dictate", {
  label = "Speech to Text",
  intent = "Start dictating; the spoken words are typed where the cursor is, with media paused.",
  run = Cmd("~/.config/hypr/scripts/voxtype-with-media-pause.sh"),
})

Act.define("voice.command", {
  label = "Voice Command",
  intent = "Listen for one spoken voice command.",
  run = Cmd(voxcmd, "listen"),
})

Act.define("voice.stop", {
  label = "Stop Voice",
  intent = "End the voice session, a waiting picker and any recording, discarding what was said.",
  run = Cmd(voxcmd, "stop"),
})

Act.define("voice.rapid", {
  label = "Rapid Mode",
  intent = "Toggle rapid voice-command mode.",
  run = Cmd(voxcmd, "session", "rapid"),
})

Act.define("voice.wake", {
  label = "Wake Word",
  intent = "Toggle wake-word listening.",
  run = Cmd(voxcmd, "wake", "toggle"),
})

Act.define("picker.passwords", {
  label = "Passwords",
  intent = "Pick a password-manager entry.",
  run = Cmd("rofi-rbw"),
})

Act.define("overview.search", {
  label = "Search windows",
  intent = "Open the workspace overview with window search active.",
  run = Ipc("overview", "search"),
})

Act.define("overview.move", {
  label = "Move window in overview",
  intent = "Open the overview carrying the focused window, and follow it to the workspace it is dropped on.",
  run = Ipc("overview", "move_follow"),
})

Act.define("overview.move_silent", {
  label = "Silent move window in overview",
  intent = "Open the overview carrying the focused window, and stay on the current workspace when it is dropped.",
  run = Ipc("overview", "move_silent"),
})

Act.define("overview.open", {
  label = "Workspace overview",
  intent = "Open the workspace overview.",
  run = Ipc("overview", "open"),
})

Act.define("tmux.overview", {
  label = "Tmux overview",
  intent = "Open the tmux session overview.",
  run = Ipc("tmux_overview", "open"),
})
