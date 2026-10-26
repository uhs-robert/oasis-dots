-- Actions for the global window keys: help, close, fullscreen, focus and move, scratchpad and monitors. The performers
-- stay in lib/actions/window.lua and are required on use, so a headless load needs neither Config nor the session.
-- Actions with a param have no default key: keymaps/global/general.lua binds each one with Act.bind, because the key
-- set follows Config (vim_mode, monitor count).
local Act = require("lib.act") ---@class ActionLib

--- Run `Window[name](...)` on each key press; the performers return a closure.
--- @param name string
--- @param ...  any   Fixed arguments for the performer
--- @return fun()
local function window(name, ...)
  local fixed = { ... }
  return function() require("lib.actions.window")[name](table.unpack(fixed))() end
end

-- Direction words the keys pass; Window.focus_dir and move_dir take Hyprland's one-letter codes.
local DIRECTION_CODE = { left = "l", down = "d", up = "u", right = "r" }
local DIRECTIONS = { "left", "down", "up", "right" }

Act.define("help.keybinds", {
  label = "Keybind Help",
  intent = "Show every key that works right now.",
  key = { key = "SLASH", leader = true, universal = true },
  run = function() require("lib.actions.menu").keybinds()() end,
})

Act.define("window.close", {
  label = "Close Window",
  intent = "Close the focused window so Restore Closed Window can bring it back.",
  key = { key = "X", leader = true },
  run = window("close"),
})

Act.define("window.kill", {
  label = "Kill Window",
  intent = "Kill the focused window's process so Restore Closed Window can bring it back.",
  run = window("kill"),
})

Act.define("window.fullscreen", {
  label = "Toggle Fullscreen",
  intent = "Make the focused window fullscreen, or put it back.",
  key = { key = "F", leader = true },
  run = window("fullscreen_toggle"),
})

Act.define("window.maximize", {
  label = "Toggle Maximize",
  intent = "Maximize the focused window inside the frame and bar, or put it back.",
  key = { key = "M", leader = true },
  run = window("maximize_toggle"),
})

Act.define("window.restore_closed", {
  label = "Restore Closed Window",
  intent = "Reopen the window closed last.",
  key = { key = "U", leader = true },
  run = window("restore_closed"),
})

Act.define("window.focus", {
  label = "Focus",
  intent = "Focus the neighbouring window in a direction.",
  params = { { name = "dir", type = "enum", values = DIRECTIONS } },
  run = function(dir) require("lib.actions.window").focus_dir(DIRECTION_CODE[dir])() end,
})

Act.define("window.move", {
  label = "Move Window",
  intent = "Move the focused window one place in a direction.",
  params = { { name = "dir", type = "enum", values = DIRECTIONS } },
  run = function(dir) require("lib.actions.window").move_dir(DIRECTION_CODE[dir])() end,
})

Act.define("window.cycle_float", {
  label = "Cycle Toast/Popup/Float",
  intent = "Focus the previous or next notification toast, else bar popup, else floating window.",
  params = { { name = "dir", type = "enum", values = { "prev", "next" } } },
  run = function(dir) require("lib.actions.window").focus_toast_popup_or_float(dir)() end,
})

Act.define("scratchpad.toggle", {
  label = "Toggle Scratchpad",
  intent = "Show or hide the scratchpad.",
  key = { key = "S", leader = true, universal = true },
  run = window("toggle_special", "scratchpad"),
})

Act.define("scratchpad.move", {
  label = "Move to Scratchpad",
  intent = "Send the focused window to the scratchpad.",
  key = { key = "SHIFT + S", leader = true, universal = true },
  run = window("move_to_special", "scratchpad"),
})

Act.define("monitor.focus", {
  label = "Focus Monitor",
  intent = "Focus the monitor in a slot (1 is the first in the machine config).",
  params = { { name = "n", type = "int" } },
  run = function(n) require("lib.actions.window").focus_monitor(n)() end,
})

Act.define("monitor.move_window", {
  label = "Move to Monitor",
  intent = "Move the focused window to the monitor in a slot and follow it.",
  params = { { name = "n", type = "int" } },
  run = function(n) require("lib.actions.window").move_to_monitor(n)() end,
})
