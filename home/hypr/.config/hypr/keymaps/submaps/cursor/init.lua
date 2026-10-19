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
  Cursor.hold_stop()
  hl.dispatch(hl.dsp.exec_cmd("pkill wl-kbptr"))
end

--- Wrap `fn` so it runs then resets the submap.
--- @param fn fun()
--- @return fun()
local function oneshot(fn)
  return function()
    fn()
    Submap.reset()
  end
end

--- Build scroll bind rows for a modifier tier. Scrolling repeats through Cursor.hold, whose release rows
--- come from scroll_release_binds.
--- @param mod string
--- @param step number
--- @param suffix string
--- @return table[]
local function scroll_binds(mod, step, suffix)
  local p = mod ~= "" and (mod .. " + ") or ""
  local s = Cursor.scroll(step)
  return {
    { p .. "E", Cursor.hold(s.up), "Scroll Up" .. suffix },
    { p .. "Y", Cursor.hold(s.down), "Scroll Down" .. suffix },
    { p .. "COMMA", Cursor.hold(s.left), "Scroll Left" .. suffix },
    { p .. "PERIOD", Cursor.hold(s.right), "Scroll Right" .. suffix },
  }
end

--- Release rows that end a held scroll. They ignore modifiers so letting go of SHIFT or CTRL first still stops it.
--- @return table[]
local function scroll_release_binds()
  local rows = {}
  for _, key in ipairs({ "E", "Y", "COMMA", "PERIOD" }) do
    rows[#rows + 1] = { key, Cursor.hold_stop, nil, { release = true, ignore_mods = true } }
  end
  return rows
end

--- Letter sets bound per Config.input.pointer_keys; the arrow keys come with the first set only.
local POINTER_KEY_SETS = {
  hjkl = { Direction.key_sets.hjkl },
  wasd = { Direction.key_sets.wasd },
  both = { Direction.key_sets.hjkl, { left = "A", down = "S", up = "W", right = "D", arrows = false } },
}

local cursor_mode = Submap.define({
  name = "Cursor",
  desc = "+Cursor",
  enter = Config.leader .. " + C",
  escape = "reset",
  catchall = "stay",
  on_enter = enter_cursor,
  on_exit = exit_cursor,

  binds = function()
    local mode = POINTER_KEY_SETS[Config.input.pointer_keys] and Config.input.pointer_keys or "hjkl"
    local key_sets = POINTER_KEY_SETS[mode]
    -- CTRL + D is the 1px right step once WASD moves the pointer
    local page_down = mode == "hjkl" and "D" or "N"
    -- stylua: ignore start
    local keys = {
      -- quick_click
      { "SEMICOLON",          Cursor.kbptr("floating_click",   { exit = true }),  "Floating Click (Exit)" },
      { Config.leader .. " + SEMICOLON",  Cursor.kbptr("floating_click",   { exit = true })},
      { "SHIFT + SEMICOLON",  Cursor.kbptr("tile_click",       { exit = true }),  "Tiling Click (Exit)" },
      { "APOSTROPHE",         Cursor.kbptr("floating_r_click", { exit = false }), "Floating Right Click"} ,
      { "SHIFT + APOSTROPHE", Cursor.kbptr("tile_r_click",     { exit = false }), "Tiling Right Click"} ,
      -- wl-kbptr modes (bare=left, SHIFT=right, CTRL=move)
      { "F",              Cursor.kbptr("floating_click"),                      "Floating Click" },
      { "SHIFT + F",      Cursor.kbptr("floating_r_click", { exit = false }),  "Floating Right Click" },
      { "CTRL + F",       Cursor.kbptr("floating_move"),                       "Floating Move" },
      { "T",              Cursor.kbptr("tile_click"),                          "Tiling Click" },
      { "SHIFT + T",      Cursor.kbptr("tile_r_click",     { exit = false }),  "Tiling Right Click" },
      { "CTRL + T",       Cursor.kbptr("tile_move"),                           "Tiling Move" },
      { "G",              Cursor.kbptr("split_click"),                         "Split Click" },
      { "SHIFT + G",      Cursor.kbptr("split_r_click", { exit = false }),     "Split Right Click" },
      { "CTRL + G",       Cursor.kbptr("split_move"),                          "Split Move" },
      -- Clicks (CTRL=exit after), the same in every pointer_keys mode
      { "SPACE",          Cursor.click_left(),                "Left Click" },
      { "CTRL + SPACE",   oneshot(Cursor.click_left()),       "Left Click (Exit)" },
      { "R",              Cursor.click_right(),               "Right Click" },
      { "CTRL + R",       oneshot(Cursor.click_right()),      "Right Click (Exit)" },
      { "M",              Cursor.click_middle(),              "Middle Click" },
      { "CTRL + M",       oneshot(Cursor.click_middle()),     "Middle Click (Exit)" },
      -- PageUp/PageDown
      { "CTRL + U",       Cursor.send_key("prior"), "Page Up" },
      { "CTRL + " .. page_down, Cursor.send_key("next"), "Page Down" },
    }
    -- stylua: ignore end

    for _, set in ipairs(key_sets) do
      -- Arrow key movement (backup for page movement)
      local arrow_keys = {
        { set.left, "LEFT", "Arrow Left" },
        { set.down, "DOWN", "Arrow Down" },
        { set.up, "UP", "Arrow Up" },
        { set.right, "RIGHT", "Arrow Right" },
      }
      for _, arrow in ipairs(arrow_keys) do
        keys[#keys + 1] = { "ALT + " .. arrow[1], Cursor.send_key(arrow[2]), arrow[3], { repeating = true } }
      end

      -- Cursor movement speed tiers with repeating
      for _, key in ipairs(Direction.speed_binds(Cursor.move, "Cursor", nil, set)) do
        key[4] = key[4] or {}
        key[4].repeating = true
        keys[#keys + 1] = key
      end

      -- Diagonal (omni-direction) speed tiers with repeating
      for _, key in ipairs(Direction.omni_binds(Cursor.move, "Cursor", nil, set)) do
        key[4] = key[4] or {}
        key[4].repeating = true
        keys[#keys + 1] = key
      end
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
    for _, key in ipairs(scroll_release_binds()) do
      keys[#keys + 1] = key
    end

    return keys
  end,
})

local SUB_QUICK = Config.leader .. " + SEMICOLON"
local quick_click = Submap.define({
  name = "Quick Click",
  desc = "+Quick Click",
  enter = SUB_QUICK,
  escape = "reset",
  catchall = "stay",
  on_enter = enter_cursor,
  on_exit = exit_cursor,

  binds = function()
    -- stylua: ignore start
    local keys = {
      -- quick_click
      { "SEMICOLON",          Cursor.kbptr("floating_click", { exit = true }),    "Floating Click (Exit)" },
      { "APOSTROPHE",         Cursor.kbptr("floating_r_click", { exit = false }), "Floating Right Click" },
      { "SHIFT + SEMICOLON",  Cursor.kbptr("tile_click", { exit = true }),        "Tile Click (Exit)" },
      -- quicker_click
      { Config.leader .. " + SEMICOLON",  Cursor.kbptr("floating_click", { exit = true })},
      { Config.leader .. " + APOSTROPHE", Cursor.kbptr("floating_r_click", { exit = false })},
      -- wl-kbptr modes
      { "F",                  Cursor.kbptr("floating_click"),                      "Floating Click" },
      { "SHIFT + F",          Cursor.kbptr("floating_r_click", { exit = false }), "Floating Right Click" },
      { "CTRL + F",           Cursor.kbptr("floating_move"),                      "Floating Move" },
      { "T",                  Cursor.kbptr("tile_click"),                         "Tiling Click" },
      { "SHIFT + T",          Cursor.kbptr("tile_r_click", { exit = false }),     "Tile Right Click" },
      { "CTRL + T",           Cursor.kbptr("tile_move"),                          "Tiling Move" },
      { "G",                  Cursor.kbptr("split_click"),                        "Split Click" },
      { "SHIFT + G",          Cursor.kbptr("split_r_click", { exit = false }),    "Split Right Click" },
      { "CTRL + G",           Cursor.kbptr("split_move"),                         "Split Move" },
    }
    -- stylua: ignore end

    return keys
  end,
})

quick_click.setup()
cursor_mode.setup()
