-- Actions for the Groups submap. Keyless: the Groups rows bind them. Focus and the other window keys reuse `window.*`.
local Act = require("lib.act") ---@class ActionLib
local Defer = require("lib.act.defer") ---@class Defer

local DIRECTION_CODE = { left = "l", down = "d", up = "u", right = "r" }

Act.define("groups.toggle", {
  label = "Toggle Group",
  intent = "Turn the focused window into a group, or ungroup it.",
  run = Defer.call("lib.actions.window", "group_toggle"),
})

Act.define("groups.next", {
  label = "Next Group Window",
  intent = "Show the next window in the focused group.",
  run = Defer.call("lib.actions.window", "group_next"),
})

Act.define("groups.prev", {
  label = "Previous Group Window",
  intent = "Show the previous window in the focused group.",
  run = Defer.call("lib.actions.window", "group_prev"),
})

Act.define("groups.move_out", {
  label = "Move Out of Group",
  intent = "Take the focused window out of its group.",
  run = Defer.call("lib.actions.window", "group_move_out"),
})

Act.define("groups.lock_toggle", {
  label = "Toggle Group Lock",
  intent = "Lock or unlock the focused group so windows cannot join it.",
  run = Defer.call("lib.actions.window", "group_lock_toggle"),
})

Act.define("groups.move", {
  label = "Move into Group",
  intent = "Move the focused window into the group in a direction, or start a group with the window there.",
  params = { { name = "dir", type = "enum", values = { "left", "down", "up", "right" } } },
  run = function(dir) require("lib.actions.window").group_move_or_create(DIRECTION_CODE[dir])() end,
})
