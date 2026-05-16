--- Cursor submap — entered with SUPER+X.
--- Keyboard-driven cursor movement, clicking, and scrolling.
--- on_enter saves and clears cursor hide/timeout config; on_exit restores it.
--- Catchall = "stay" swallows unbound key presses.
local Config    = require("config")
local Direction = require("lib.key.direction")
local Submap    = require("lib.key.submap")
local Cursor    = require("lib.actions.cursor")

--- Saved cursor config, populated on_enter and restored on_exit.
--- @type { hide: boolean, timeout: number }
local defaults = {}

local function restore()
  hl.config({ cursor = { inactive_timeout = defaults.timeout, hide_on_key_press = defaults.hide } })
  hl.dispatch(hl.dsp.exec_cmd("pkill wl-kbptr"))
end

--- Run a wl-kbptr command then re-enter cursor submap (stay in mode).
local function kbptr_stay(cmd)
  return function()
    hl.dispatch(hl.dsp.exec_cmd(cmd))
    Submap.enter("Cursor")
  end
end

--- Run a wl-kbptr command then exit cursor submap entirely.
local function kbptr_exit(cmd)
  return function()
    hl.dispatch(hl.dsp.exec_cmd(cmd))
    Submap.reset()
  end
end

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
    { p .. "E",      s.up,    "Scroll Up"    .. suffix, rep },
    { p .. "Y",      s.down,  "Scroll Down"  .. suffix, rep },
    { p .. "COMMA",  s.left,  "Scroll Left"  .. suffix, rep },
    { p .. "PERIOD", s.right, "Scroll Right" .. suffix, rep },
  }
end

local cursor_mode = Submap.define({
  name  = "Cursor",
  desc  = "+Cursor",
  enter = Config.leader .. " + X",

  escape   = "reset",
  catchall = "stay",

  on_enter = function()
    defaults.hide    = hl.get_config("cursor.hide_on_key_press")
    defaults.timeout = hl.get_config("cursor.inactive_timeout")
    hl.config({ cursor = { inactive_timeout = 0, hide_on_key_press = false } })
  end,

  on_exit = function()
    restore()
  end,

  binds = function()
    local rows = {}

    -- Cursor movement speed tiers (H/J/K/L)
    for _, row in ipairs(Direction.speed_binds(Cursor.move, "Cursor")) do
      row[4] = row[4] or {}
      row[4].repeating = true
      table.insert(rows, row)
    end

    -- Scroll tiers (E/Y/COMMA/PERIOD)
    for _, row in ipairs(scroll_binds("",       10,  ""))           do table.insert(rows, row) end
    for _, row in ipairs(scroll_binds("SHIFT",  100, " (Fast)"))    do table.insert(rows, row) end
    for _, row in ipairs(scroll_binds("CTRL",   1,   " (Pixel)"))   do table.insert(rows, row) end

    -- stylua: ignore start

    -- wl-kbptr modes (stay)
    table.insert(rows, { "F",           kbptr_stay("wl-kbptr -o modes=floating,click -o mode_floating.source=detect"), "Floating Click" })
    table.insert(rows, { "SHIFT + F",   kbptr_stay("wl-kbptr -o modes=floating -o mode_floating.source=detect"),       "Floating Move" })
    table.insert(rows, { "T",           kbptr_stay("wl-kbptr -o modes=tile,click"),                                    "Tiling Click" })
    table.insert(rows, { "SHIFT + T",   kbptr_stay("wl-kbptr -o modes=tile"),                                          "Tiling Move" })

    -- wl-kbptr modes (exit)
    table.insert(rows, { "CTRL + F",    kbptr_exit("wl-kbptr -o modes=floating,click -o mode_floating.source=detect"), "Floating Click (Exit)" })
    table.insert(rows, { "CTRL + T",    kbptr_exit("wl-kbptr -o modes=tile,click"),                                    "Tiling Click (Exit)" })

    -- Clicks (stay)
    table.insert(rows, { "SPACE",        Cursor.click_left(),   "Left Click" })
    table.insert(rows, { "A",            Cursor.click_left(),   "Left Click" })
    table.insert(rows, { "S",            Cursor.click_middle(), "Middle Click" })
    table.insert(rows, { "D",            Cursor.click_right(),  "Right Click" })
    table.insert(rows, { "CTRL + SPACE", Cursor.click_right(),  "Right Click" })
    table.insert(rows, { "SHIFT + SPACE", Cursor.click_middle(), "Middle Click" })

    -- Clicks (exit)
    table.insert(rows, { "CTRL + A", function() Cursor.click_left()();   Submap.reset() end, "Left Click (Exit)" })
    table.insert(rows, { "CTRL + S", function() Cursor.click_middle()(); Submap.reset() end, "Middle Click (Exit)" })

    -- Arrow key backup movement
    table.insert(rows, { "ALT + H", Cursor.send_key("LEFT"),  "Arrow Left",  { repeating = true } })
    table.insert(rows, { "ALT + J", Cursor.send_key("DOWN"),  "Arrow Down",  { repeating = true } })
    table.insert(rows, { "ALT + K", Cursor.send_key("UP"),    "Arrow Up",    { repeating = true } })
    table.insert(rows, { "ALT + L", Cursor.send_key("RIGHT"), "Arrow Right", { repeating = true } })

    -- PageUp/PageDown backup
    table.insert(rows, { "CTRL + U", Cursor.send_key("prior"), "Page Up" })
    table.insert(rows, { "CTRL + D", Cursor.send_key("next"),  "Page Down" })

    -- Submap switches (on_exit fires automatically via Submap.enter)
    table.insert(rows, { "W",          function() Submap.enter("Windows") end,    "+Windows" })
    table.insert(rows, { "R",          function() Submap.enter("Resize") end,     "+Resize" })
    table.insert(rows, { "I",          function() Submap.enter("Screenshot") end, "+Screenshot" })
    table.insert(rows, { "Q",          function() Submap.enter("System") end,     "+System" })

    -- WhichKey
    table.insert(rows, { "SHIFT + SLASH", function() require("hyprvim.whichkey").toggle() end, "WhichKey" })
    -- stylua: ignore end

    return rows
  end,
})

return cursor_mode
