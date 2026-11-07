--- Cursor submap
--- Keyboard-driven cursor movement, clicking, and scrolling.

local Config = require("config") ---@class Config
local Direction = require("lib.key.direction") ---@class Direction
local Submap = require("lib.key.submap") ---@class Submap

-- The actions the rows name.
require("lib.act.defs.cursor")

--- Saved cursor config, populated on_enter and restored on_exit.
--- @type { hide: boolean, timeout: number }
local DEFAULTS = {}

--- Save cursor config, disable hide/timeout and warm up the ydotoold daemon for drags. Called on submap enter.
local enter_cursor = function()
  require("lib.desktop.cursor").daemon_start()
  DEFAULTS.hide = hl.get_config("cursor.hide_on_key_press")
  DEFAULTS.timeout = hl.get_config("cursor.inactive_timeout")
  hl.config({ cursor = { inactive_timeout = 0, hide_on_key_press = false } })
end

--- Restore cursor config, let go of any held drag, stop the ydotoold daemon unless the next submap is the other Cursor
--- one, and kill wl-kbptr. Called on submap exit.
--- @param ctx SubmapContext
local function exit_cursor(ctx)
  hl.config({ cursor = { inactive_timeout = DEFAULTS.timeout, hide_on_key_press = DEFAULTS.hide } })
  local cursor = require("lib.desktop.cursor")
  cursor.hold_stop()
  cursor.drag_submap_exit(ctx and ctx.to)
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

--- Esc cancels a live drag and keeps the submap open; with none it leaves the submap.
local function escape_cursor()
  local cursor = require("lib.desktop.cursor")
  if cursor.drag_active() then return cursor.drag_cancel() end
  Submap.reset()
end

--- Rows that start a drag, shared by both submaps. Dropping is the Cursor submap's left-click key (see cursor.click).
--- Plain V grabs and moves by hand, which needs the Cursor submap's move keys, so Quick Click has only the picking
--- variants, which drop on their own at the target.
--- @param manual boolean
--- @return table[]
local function drag_rows(manual)
  local rows = {}
  if manual then rows[#rows + 1] = { "V", { "cursor.drag_start", { "manual" } }, "Drag (Grab)" } end
  rows[#rows + 1] = { "SHIFT + V", { "cursor.drag_start", { "find" } }, "Drag to Find Pick" }
  rows[#rows + 1] = { "CTRL + V", { "cursor.drag_start", { "tile" } }, "Drag to Tile Pick" }
  rows[#rows + 1] = { "ALT + V", { "cursor.drag_start", { "split" } }, "Drag to Split Pick" }
  return rows
end

--- The four pointer directions as actions that move by `amount` pixels. Holding two of them moves diagonally.
--- @param amount number
--- @return DirActions
local function move_by(amount)
  return {
    left = { "cursor.move", { "left", amount } },
    right = { "cursor.move", { "right", amount } },
    up = { "cursor.move", { "up", amount } },
    down = { "cursor.move", { "down", amount } },
  }
end

--- Options for the release rows that end a held move or scroll. ignore_mods: letting go of SHIFT or CTRL first still
--- stops it, and the row claims the key-down of every modifier combo, so one with no bind of its own (ALT + LEFT)
--- never reaches the focused app. transparent: Hyprland 0.57 shadows a held key's release bind once another key is
--- pressed or released (shadowBinds), so without it the release after a diagonal never runs and the pointer moves
--- forever.
local function held_release() return { release = true, ignore_mods = true, transparent = true } end

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

--- Release rows that end a held scroll.
--- @return table[]
local function scroll_release_binds()
  local rows = {}
  for _, key in ipairs({ "E", "Y", "COMMA", "PERIOD" }) do
    rows[#rows + 1] = { key, "cursor.scroll_stop", false, held_release() }
  end
  return rows
end

--- Release rows that let go of a held move direction.
--- @param set DirectionKeys
--- @return table[]
local function move_release_binds(set)
  local rows = {}
  local function add(key, dir) rows[#rows + 1] = { key, { "cursor.move_stop", { dir } }, false, held_release() } end
  for _, dir in ipairs({ "left", "down", "up", "right" }) do
    add(set[dir], dir)
    if set.arrows ~= false then add(dir:upper(), dir) end
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
  escape = escape_cursor,
  escape_label = "Cancel/Exit",
  catchall = "stay",
  on_enter = enter_cursor,
  on_exit = exit_cursor,

  -- The scroll speeds and the Shift and Ctrl wl-kbptr variants are left to the full list behind SHIFT + /.
  hint = {
    { "Move", { "cursor.move", label = "Move", tiers = "speed" } },
    {
      "Click",
      { "cursor.click", args = { "left" }, mods = "", label = "Left" },
      { "cursor.click", args = { "right" }, mods = "", label = "Right" },
      { "cursor.click", args = { "middle" }, mods = "", label = "Middle" },
      { "cursor.click", mods = "CTRL", label = "+Exit" },
    },
    {
      "Pick",
      { "cursor.pointer_mode", args = { "floating_click", false }, mods = "", label = "Float" },
      { "cursor.pointer_mode", args = { "tile_click" }, mods = "", label = "Tile" },
      { "cursor.pointer_mode", args = { "split_click" }, mods = "", label = "Split" },
      { "cursor.pointer_mode", args = { "floating_click", true }, mods = "", label = "Quick" },
    },
    {
      "Drag",
      { "cursor.drag_start", args = { "manual" }, label = "Grab" },
      { "cursor.drag_start", args = { "find" }, label = "Find" },
      { "cursor.drag_start", args = { "tile" }, label = "Tile" },
      { "cursor.drag_start", args = { "split" }, label = "Split" },
      { "cursor.click", args = { "left" }, label = "Drop" },
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

    for _, row in ipairs(drag_rows(true)) do
      keys[#keys + 1] = row
    end

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

      -- Speed tiers. cursor.move repeats on its own until the release rows let go, so Hyprland's repeat stays off.
      for _, key in ipairs(Direction.speed_binds(move_by, "Cursor", nil, set)) do
        key[4] = nil
        keys[#keys + 1] = key
      end
      for _, key in ipairs(move_release_binds(set)) do
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
  escape = escape_cursor,
  escape_label = "Cancel/Exit",
  catchall = "stay",
  on_enter = enter_cursor,
  on_exit = exit_cursor,

  hint = {
    {
      "Pick",
      { "cursor.pointer_mode", args = { "floating_click", false }, mods = "", label = "Float" },
      { "cursor.pointer_mode", args = { "tile_click" }, mods = "", label = "Tile" },
      { "cursor.pointer_mode", args = { "split_click" }, mods = "", label = "Split" },
    },
    {
      "Drag",
      { "cursor.drag_start", args = { "find" }, label = "Find" },
      { "cursor.drag_start", args = { "tile" }, label = "Tile" },
      { "cursor.drag_start", args = { "split" }, label = "Split" },
    },
  },

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

    for _, row in ipairs(drag_rows(false)) do
      keys[#keys + 1] = row
    end

    return keys
  end,
})

quick_click.setup()
cursor_mode.setup()
