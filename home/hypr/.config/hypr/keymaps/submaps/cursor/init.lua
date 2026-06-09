--- Cursor submap
--- Keyboard-driven cursor movement, clicking, and scrolling.

local Config = require("config") ---@class Config
local Direction = require("lib.key.direction") ---@class Direction
local Submap = require("lib.key.submap") ---@class Submap
local Cursor = require("lib.actions.cursor") ---@class CursorActions

--- Saved cursor config, populated on_enter and restored on_exit.
--- @type { hide: boolean, timeout: number }
local DEFAULTS = {}

--- Save cursor config and disable hide/timeout. Called on submap enter.
local enter_cursor = function()
  DEFAULTS.hide = hl.get_config("cursor.hide_on_key_press")
  DEFAULTS.timeout = hl.get_config("cursor.inactive_timeout")
  hl.config({ cursor = { inactive_timeout = 0, hide_on_key_press = false } })
end

--- Restore cursor config and kill wl-kbptr. Called on submap exit.
local function exit_cursor()
  hl.config({ cursor = { inactive_timeout = DEFAULTS.timeout, hide_on_key_press = DEFAULTS.hide } })
  hl.dispatch(hl.dsp.exec_cmd("pkill wl-kbptr"))
end

--- Wrap `fn` so it runs then resets or switches to another submap.
--- @param fn fun()
--- @param to_submap nil | string
--- @return fun()
-- stylua: ignore
local function oneshot(fn, to_submap)
  return function()
    fn()
    if to_submap then Submap.switch(to_submap) else Submap.reset() end
  end
end

--- Wrap `fn` so it runs then switches to Cursor submap.
--- @param fn fun()
--- @return fun()
local function to_cursor(fn) return oneshot(fn, "Cursor") end

--- Build scroll bind rows for a modifier tier.
--- @param mod string
--- @param step number
--- @param suffix string
--- @return table[]
local function scroll_binds(mod, step, suffix)
  local p = mod ~= "" and (mod .. " + ") or ""
  local rep = { repeating = true }
  local s = Cursor.scroll(step)
  return {
    { p .. "E", s.up, "Scroll Up" .. suffix, rep },
    { p .. "Y", s.down, "Scroll Down" .. suffix, rep },
    { p .. "COMMA", s.left, "Scroll Left" .. suffix, rep },
    { p .. "PERIOD", s.right, "Scroll Right" .. suffix, rep },
  }
end

local cursor_mode = Submap.define({
  name = "Cursor",
  desc = "+Cursor",
  enter = Config.leader .. " + X",
  escape = "reset",
  catchall = "stay",
  on_enter = enter_cursor,
  on_exit = exit_cursor,

  binds = function()
    -- stylua: ignore start
    local keys = {
      -- quick_click
      { "SEMICOLON",          Cursor.kbptr("floating_click", { exit = true }),  "Floating Click (Exit)" },
      { "SHIFT + SEMICOLON",  Cursor.kbptr("tile_click", { exit = true }),      "Tile Click (Exit)" },
      -- wl-kbptr modes
      { "F",              Cursor.kbptr("floating_click"),                   "Floating Click" },
      { "CTRL + F",       Cursor.kbptr("floating_click", { exit = true }),  "Floating Click (Exit)" },
      { "SHIFT + F",      Cursor.kbptr("floating_move"),                    "Floating Move" },
      { "T",              Cursor.kbptr("tile_click"),                       "Tiling Click" },
      { "CTRL + T",       Cursor.kbptr("tile_click",     { exit = true }),  "Tiling Click (Exit)" },
      { "SHIFT + T",      Cursor.kbptr("tile_move"),                        "Tiling Move" },
      -- Clicks
      { "SPACE",          Cursor.click_left(),             "Left Click" },
      { "A",              Cursor.click_left(),             "Left Click" },
      { "CTRL + A",       oneshot(Cursor.click_left()),    "Left Click (Exit)" },
      { "S",              Cursor.click_middle(),           "Middle Click" },
      { "CTRL + S",       oneshot(Cursor.click_middle()),  "Middle Click (Exit)" },
      { "D",              Cursor.click_right(),            "Right Click" },
      { "CTRL + SPACE",   Cursor.click_right(),            "Right Click" },
      { "SHIFT + SPACE",  Cursor.click_middle(),           "Middle Click" },
      -- PageUp/PageDown
      { "CTRL + U",       Cursor.send_key("prior"), "Page Up" },
      { "CTRL + D",       Cursor.send_key("next"),  "Page Down" },
      -- Arrow key movement (backup for page movement)
      { "ALT + H",        Cursor.send_key("LEFT"),  "Arrow Left",  { repeating = true } },
      { "ALT + J",        Cursor.send_key("DOWN"),  "Arrow Down",  { repeating = true } },
      { "ALT + K",        Cursor.send_key("UP"),    "Arrow Up",    { repeating = true } },
      { "ALT + L",        Cursor.send_key("RIGHT"), "Arrow Right", { repeating = true } },
      -- Submap switches
      { "W",              Submap.switch("Windows"),     "+Windows" },
      { "R",              Submap.switch("Resize"),      "+Resize" },
      { "I",              Submap.switch("Screenshot"),  "+Screenshot" },
      { "Q",              Submap.switch("System"),      "+System" },
      -- WhichKey
      { "SHIFT + SLASH",  function() require("lua.plugins.hyprvim").whichkey.toggle() end, "WhichKey" },
    }
    -- stylua: ignore end

    -- Cursor movement speed tiers (H/J/K/L) with repeating
    for _, key in ipairs(Direction.speed_binds(Cursor.move, "Cursor")) do
      key[4] = key[4] or {}
      key[4].repeating = true
      keys[#keys + 1] = key
    end

    -- Scroll tiers (E/Y/COMMA/PERIOD)
    for _, key in ipairs(scroll_binds("", 10, "")) do
      keys[#keys + 1] = key
    end
    for _, key in ipairs(scroll_binds("SHIFT", 100, " (Fast)")) do
      keys[#keys + 1] = key
    end
    for _, key in ipairs(scroll_binds("CTRL", 1, " (Pixel)")) do
      keys[#keys + 1] = key
    end

    return keys
  end,
})

local quick_click = Submap.define({
  name = "Quick Click",
  desc = "+Quick Click",
  enter = Config.leader .. " + SEMICOLON",
  escape = "reset",
  catchall = "stay",
  on_enter = enter_cursor,
  on_exit = exit_cursor,

  binds = function()
    -- stylua: ignore start
    local keys = {
      -- quick_click
      { "SEMICOLON",          Cursor.kbptr("floating_click", { exit = true }),  "Floating Click (Exit)" },
      { "SHIFT + SEMICOLON",  Cursor.kbptr("tile_click", { exit = true }),      "Tile Click (Exit)" },
      -- wl-kbptr modes
      { "F",                  to_cursor(Cursor.kbptr("floating_click")),        "Floating Click" },
      { "SHIFT + F",          to_cursor(Cursor.kbptr("floating_move")),         "Floating Move" },
      { "T",                  to_cursor(Cursor.kbptr("tile_click")),            "Tiling Click" },
      { "SHIFT + T",          to_cursor(Cursor.kbptr("tile_move")),             "Tiling Move" },
      -- WhichKey
      { "SHIFT + SLASH",  function() require("lua.plugins.hyprvim").whichkey.toggle() end, "WhichKey" },
    }
    -- stylua: ignore end

    return keys
  end,
})

quick_click.setup()
cursor_mode.setup()
