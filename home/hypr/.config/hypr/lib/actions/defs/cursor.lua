-- Actions for the Cursor submap: pointer movement, scrolling, clicks and wl-kbptr. Keyless; the Cursor and Quick Click
-- rows bind them. Held scrolling keeps its timers in lib/actions/cursor.lua, so a release row stops what a press
-- started whichever submap bound it.
local Act = require("lib.act") ---@class ActionLib

-- Pointer directions; "up_left" and the rest are the diagonal chords.
local MOVE_DIRECTIONS = { "left", "down", "up", "right", "up_left", "up_right", "down_left", "down_right" }
local MOVE_KEY = {
  left = "left",
  down = "down",
  up = "up",
  right = "right",
  up_left = "nw",
  up_right = "ne",
  down_left = "sw",
  down_right = "se",
}
local SCROLL_DIRECTIONS = { "up", "down", "left", "right" }
local KBPTR_MODES = {
  "floating_click",
  "floating_move",
  "floating_r_click",
  "tile_click",
  "tile_move",
  "tile_r_click",
  "split_click",
  "split_move",
  "split_r_click",
}
local CLICK_BUTTONS = { "left", "right", "middle" }

--- @return CursorActions
local function cursor() return require("lib.actions.cursor") end

Act.define("cursor.move", {
  label = "Move Pointer",
  intent = "Move the mouse pointer by a number of pixels in a direction, diagonals included.",
  params = {
    { name = "dir", type = "enum", values = MOVE_DIRECTIONS },
    { name = "amount", type = "int" },
  },
  run = function(dir, amount) cursor().move(amount)[MOVE_KEY[dir]]() end,
})

Act.define("cursor.scroll", {
  label = "Scroll",
  intent = "Scroll by a step in a direction and keep repeating until cursor.scroll_stop runs.",
  params = {
    { name = "dir", type = "enum", values = SCROLL_DIRECTIONS },
    { name = "step", type = "int" },
  },
  run = function(dir, step) cursor().hold(cursor().scroll(step)[dir])() end,
})

Act.define("cursor.scroll_stop", {
  label = "Stop Scrolling",
  intent = "End a repeating scroll.",
  run = function() cursor().hold_stop() end,
})

Act.define("cursor.click", {
  label = "Click",
  intent = "Click a mouse button at the pointer; with exit, then leave the Cursor submap.",
  params = {
    { name = "button", type = "enum", values = CLICK_BUTTONS },
    { name = "exit", type = "bool", default = false },
  },
  run = function(button, exit)
    cursor()["click_" .. button]()()
    if exit then require("lib.key.submap").reset() end
  end,
})

Act.define("cursor.pointer_mode", {
  label = "Pointer Mode",
  intent = "Pick a screen spot with wl-kbptr (floating, tiling or split targets) and click or move there; with exit, leave the Cursor submap first.",
  params = {
    { name = "mode", type = "enum", values = KBPTR_MODES },
    { name = "exit", type = "bool", default = false },
  },
  run = function(mode, exit) cursor().kbptr(mode, { exit = exit })() end,
})

Act.define("cursor.send_key", {
  label = "Send Key",
  intent = "Send one key (such as LEFT, prior or next) to the focused window.",
  params = { { name = "key", type = "string" } },
  run = function(key) cursor().send_key(key)() end,
})
