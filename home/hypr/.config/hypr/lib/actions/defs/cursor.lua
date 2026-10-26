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

--- Whether a Cursor submap is active. Its release rows and exit hook are what stop a repeating scroll and restore the
--- cursor config on leaving, so an action called from anywhere else (hypr-act, the bar, voice) must not rely on them.
--- @return boolean
local function in_cursor_submap()
  local current = hl.get_current_submap()
  return current == "Cursor" or current == "Quick Click"
end

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
  intent = "Scroll by a step in a direction. In the Cursor submap it keeps repeating until cursor.scroll_stop runs; anywhere else it scrolls once.",
  params = {
    { name = "dir", type = "enum", values = SCROLL_DIRECTIONS },
    { name = "step", type = "int" },
  },
  run = function(dir, step)
    local scroll = cursor().scroll(step)[dir]
    if in_cursor_submap() then
      cursor().hold(scroll)()
    else
      scroll()
    end
  end,
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
  intent = "Pick a screen spot with wl-kbptr (floating, tiling or split targets) and click or move there. In the Cursor submap it returns there afterwards unless exit is set; anywhere else it never enters the submap.",
  params = {
    { name = "mode", type = "enum", values = KBPTR_MODES },
    { name = "exit", type = "bool", default = false },
  },
  -- Returning to Cursor afterwards would skip its on_enter, so outside the submap the action takes the exit path.
  run = function(mode, exit) cursor().kbptr(mode, { exit = exit or not in_cursor_submap() })() end,
})

Act.define("cursor.send_key", {
  label = "Send Key",
  intent = "Send one key (such as LEFT, prior or next) to the focused window.",
  params = { { name = "key", type = "string" } },
  run = function(key) cursor().send_key(key)() end,
})
