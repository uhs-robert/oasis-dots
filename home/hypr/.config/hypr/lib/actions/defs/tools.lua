-- Actions for the tool keys: zoom, screenshot, voice, passwords and the overviews. Defining one binds its keys.
-- Kept apart from keymaps/global/tools.lua so a headless load needs only `lib.act` and `hl.bind`, not Menu or Config.
local Act = require("lib.act") ---@class ActionLib
local Ipc, Cmd = Act.Ipc, Act.Cmd

local screenshot = "~/.config/hypr/scripts/screenshot.sh"
local voxcmd = "~/.local/bin/voxcmd"

Act.define("screenshot.take", {
  label = "Screenshot",
  intent = "Open the screenshot and recording menu.",
  key = { key = "Print", universal = true },
  extra_keys = { { key = "I", leader = true } },
  run = Cmd(screenshot),
})

Act.define("screenshot.pixel", {
  label = "Color Picker",
  intent = "Pick a color from the screen and copy it.",
  key = { key = "P", leader = true },
  run = Cmd(screenshot, "--pixel"),
})

Act.define("zoom.toggle", {
  label = "Zoom",
  intent = "Start the screen magnifier, or stop it when it is running.",
  key = { key = "Z", leader = true },
  run = Ipc("zoom", "toggle"),
})

-- While voxtype records, either key stops it and the recording's own mode handles the result.
-- Stop Voice ends everything instead.
Act.define("voice.dictate", {
  label = "Speech to Text",
  intent = "Start dictating; the spoken words are typed where the cursor is, with media paused.",
  key = { key = "PERIOD", leader = true },
  run = Cmd("~/.config/hypr/scripts/voxtype-with-media-pause.sh"),
})

Act.define("voice.command", {
  label = "Voice Command",
  intent = "Listen for one spoken voice command.",
  key = { key = "COMMA", leader = true },
  run = Cmd(voxcmd, "listen"),
})

Act.define("voice.stop", {
  label = "Stop Voice",
  intent = "End the voice session, a waiting picker and any recording, discarding what was said.",
  key = { key = "SHIFT + COMMA", leader = true },
  run = Cmd(voxcmd, "stop"),
})

Act.define("voice.rapid", {
  label = "Rapid Mode",
  intent = "Toggle rapid voice-command mode.",
  key = { key = "CTRL + COMMA", leader = true },
  run = Cmd(voxcmd, "session", "rapid"),
})

Act.define("voice.wake", {
  label = "Wake Word",
  intent = "Toggle wake-word listening.",
  key = { key = "CTRL + PERIOD", leader = true },
  run = Cmd(voxcmd, "wake", "toggle"),
})

Act.define("picker.passwords", {
  label = "Passwords",
  intent = "Pick a password-manager entry.",
  key = { key = "CTRL + P", leader = true },
  run = Cmd("rofi-rbw"),
})

Act.define("overview.search", {
  label = "Search windows",
  intent = "Open the workspace overview with window search active.",
  key = { key = "T", leader = true },
  run = Ipc("overview", "search"),
})

Act.define("overview.move", {
  label = "Move window in overview",
  intent = "Open the overview carrying the focused window, and follow it to the workspace it is dropped on.",
  key = { key = "SHIFT + T", leader = true },
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
  key = "ALT + TAB",
  extra_keys = { { key = "TAB", leader = true } },
  run = Ipc("overview", "open"),
})

Act.define("tmux.overview", {
  label = "Tmux overview",
  intent = "Open the tmux session overview.",
  key = "ALT + GRAVE",
  run = Ipc("tmux_overview", "open"),
})
