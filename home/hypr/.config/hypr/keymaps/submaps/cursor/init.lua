--- Cursor submap
--- Keyboard-driven cursor movement, clicking, and scrolling.

local Config = require("config") ---@class Config
local Direction = require("lib.key.direction") ---@class Direction
local Submap = require("lib.key.submap") ---@class Submap

-- The actions the rows name.
require("lib.actions.defs.cursor")

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
  require("lib.actions.cursor").hold_stop()
  hl.dispatch(hl.dsp.exec_cmd("pkill wl-kbptr"))
end

--- A row action for wl-kbptr; `exit` leaves the submap once the click is done.
--- @param mode string
--- @param exit boolean|nil
--- @return table
local function pointer(mode, exit) return { "cursor.pointer_mode", { mode, exit == true } } end

--- A row action for a mouse click; `exit` leaves the submap after it.
--- @param button string
--- @param exit boolean|nil
--- @return table
local function click(button, exit) return { "cursor.click", { button, exit == true } } end

--- The eight pointer directions as actions that move by `amount` pixels.
--- @param amount number
--- @return DirActions
local function move_by(amount)
  return {
    left = { "cursor.move", { "left", amount } },
    right = { "cursor.move", { "right", amount } },
    up = { "cursor.move", { "up", amount } },
    down = { "cursor.move", { "down", amount } },
    nw = { "cursor.move", { "up_left", amount } },
    ne = { "cursor.move", { "up_right", amount } },
    sw = { "cursor.move", { "down_left", amount } },
    se = { "cursor.move", { "down_right", amount } },
  }
end

--- Build scroll bind rows for a modifier tier. Scrolling repeats until the release rows from scroll_release_binds
--- stop it.
--- @param mod string
--- @param step number
--- @param suffix string
--- @return table[]
local function scroll_binds(mod, step, suffix)
  local p = mod ~= "" and (mod .. " + ") or ""
  return {
    { p .. "E", { "cursor.scroll", { "up", step } }, "Scroll Up" .. suffix },
    { p .. "Y", { "cursor.scroll", { "down", step } }, "Scroll Down" .. suffix },
    { p .. "COMMA", { "cursor.scroll", { "left", step } }, "Scroll Left" .. suffix },
    { p .. "PERIOD", { "cursor.scroll", { "right", step } }, "Scroll Right" .. suffix },
  }
end

--- Release rows that end a held scroll. They ignore modifiers so letting go of SHIFT or CTRL first still stops it.
--- @return table[]
local function scroll_release_binds()
  local rows = {}
  for _, key in ipairs({ "E", "Y", "COMMA", "PERIOD" }) do
    rows[#rows + 1] = { key, "cursor.scroll_stop", false, { release = true, ignore_mods = true } }
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

  -- The diagonal chords and the Shift and Ctrl wl-kbptr variants are left to the full list behind SHIFT + /.
  hint = {
    { "Move", { "cursor.move", label = "Move" } },
    {
      "Click",
      { "cursor.click", args = { "left" }, mods = "", label = "Left" },
      { "cursor.click", args = { "right" }, mods = "", label = "Right" },
      { "cursor.click", args = { "middle" }, mods = "", label = "Middle" },
      { "cursor.click", mods = "CTRL", label = "Click" },
    },
    {
      "Pick",
      { "cursor.pointer_mode", args = { "floating_click", false }, mods = "", label = "Float" },
      { "cursor.pointer_mode", args = { "tile_click" }, mods = "", label = "Tile" },
      { "cursor.pointer_mode", args = { "split_click" }, mods = "", label = "Split" },
      { "cursor.pointer_mode", args = { "floating_click", true }, mods = "", label = "Float" },
    },
    { "Scroll", { "cursor.scroll", label = "Scroll" } },
    {
      "Keys",
      { "cursor.send_key", mods = "ALT", label = "Arrows" },
      { "cursor.send_key", mods = "CTRL", label = "Page" },
    },
  },

  binds = function()
    local mode = POINTER_KEY_SETS[Config.input.pointer_keys] and Config.input.pointer_keys or "hjkl"
    local key_sets = POINTER_KEY_SETS[mode]
    -- CTRL + D is the 1px right step once WASD moves the pointer
    local page_down = mode == "hjkl" and "D" or "N"
    -- stylua: ignore start
    local keys = {
      -- quick_click
      { "SEMICOLON",          pointer("floating_click", true),  "Floating Click (Exit)" },
      { Config.leader .. " + SEMICOLON",  pointer("floating_click", true), false },
      { "SHIFT + SEMICOLON",  pointer("tile_click", true),  "Tiling Click (Exit)" },
      { "APOSTROPHE",         pointer("floating_r_click"), "Floating Right Click"} ,
      { "SHIFT + APOSTROPHE", pointer("tile_r_click"), "Tiling Right Click"} ,
      -- wl-kbptr modes (bare=left, SHIFT=right, CTRL=move)
      { "F",              pointer("floating_click"),                      "Floating Click" },
      { "SHIFT + F",      pointer("floating_r_click"),  "Floating Right Click" },
      { "CTRL + F",       pointer("floating_move"),                       "Floating Move" },
      { "T",              pointer("tile_click"),                          "Tiling Click" },
      { "SHIFT + T",      pointer("tile_r_click"),  "Tiling Right Click" },
      { "CTRL + T",       pointer("tile_move"),                           "Tiling Move" },
      { "G",              pointer("split_click"),                         "Split Click" },
      { "SHIFT + G",      pointer("split_r_click"),     "Split Right Click" },
      { "CTRL + G",       pointer("split_move"),                          "Split Move" },
      -- Clicks (CTRL=exit after), the same in every pointer_keys mode
      { "SPACE",          click("left"),                "Left Click" },
      { "CTRL + SPACE",   click("left", true),       "Left Click (Exit)" },
      { "R",              click("right"),               "Right Click" },
      { "CTRL + R",       click("right", true),      "Right Click (Exit)" },
      { "M",              click("middle"),              "Middle Click" },
      { "CTRL + M",       click("middle", true),     "Middle Click (Exit)" },
      -- PageUp/PageDown
      { "CTRL + U",       { "cursor.send_key", { "prior" } }, "Page Up" },
      { "CTRL + " .. page_down, { "cursor.send_key", { "next" } }, "Page Down" },
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
        keys[#keys + 1] = { "ALT + " .. arrow[1], { "cursor.send_key", { arrow[2] } }, arrow[3], { repeating = true } }
      end

      -- Cursor movement speed tiers with repeating
      for _, key in ipairs(Direction.speed_binds(move_by, "Cursor", nil, set)) do
        key[4] = key[4] or {}
        key[4].repeating = true
        keys[#keys + 1] = key
      end

      -- Diagonal (omni-direction) speed tiers with repeating
      for _, key in ipairs(Direction.omni_binds(move_by, "Cursor", nil, set)) do
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
      { "SEMICOLON",          pointer("floating_click", true),    "Floating Click (Exit)" },
      { "APOSTROPHE",         pointer("floating_r_click"), "Floating Right Click" },
      { "SHIFT + SEMICOLON",  pointer("tile_click", true),        "Tile Click (Exit)" },
      -- quicker_click
      { Config.leader .. " + SEMICOLON",  pointer("floating_click", true), false },
      { Config.leader .. " + APOSTROPHE", pointer("floating_r_click"), false },
      -- wl-kbptr modes
      { "F",                  pointer("floating_click"),                      "Floating Click" },
      { "SHIFT + F",          pointer("floating_r_click"), "Floating Right Click" },
      { "CTRL + F",           pointer("floating_move"),                      "Floating Move" },
      { "T",                  pointer("tile_click"),                         "Tiling Click" },
      { "SHIFT + T",          pointer("tile_r_click"),     "Tile Right Click" },
      { "CTRL + T",           pointer("tile_move"),                          "Tiling Move" },
      { "G",                  pointer("split_click"),                        "Split Click" },
      { "SHIFT + G",          pointer("split_r_click"),    "Split Right Click" },
      { "CTRL + G",           pointer("split_move"),                         "Split Move" },
    }
    -- stylua: ignore end

    return keys
  end,
})

quick_click.setup()
cursor_mode.setup()
