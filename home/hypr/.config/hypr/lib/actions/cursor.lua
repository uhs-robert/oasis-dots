--- Cursor actions: pointer movement, scrolling, clicking, key dispatch via wlrctl/hyprctl.

local Hypr = require("lib.hypr") --- @class HyprLib
local Submap = require("lib.key.submap") ---@class Submap

--- @class DirActions
--- @field left  function
--- @field right function
--- @field up    function
--- @field down  function
--- @field nw    function
--- @field ne    function
--- @field sw    function
--- @field se    function

--- wl-kbptr mode commands by name. They go through kbptr.sh, which does the move and click itself.
local KBPTR = "~/.config/hypr/scripts/kbptr.sh"
local KBPTR_CMDS = {
  floating_click = KBPTR .. " -o modes=floating,click -o mode_floating.source=detect",
  floating_move = KBPTR .. " -o modes=floating -o mode_floating.source=detect",
  floating_r_click = KBPTR .. " -o modes=floating -o mode_floating.source=detect ; wlrctl pointer click right",
  tile_click = KBPTR .. " -o modes=tile,click",
  tile_move = KBPTR .. " -o modes=tile",
  tile_r_click = KBPTR .. " -o modes=tile ; wlrctl pointer click right",
  split_click = KBPTR .. " -o modes=split,click",
  split_move = KBPTR .. " -o modes=split",
  split_r_click = KBPTR .. " -o modes=split ; wlrctl pointer click right",
}

--- @class CursorActions
local Cursor = {
  click_left = function() return Hypr.exec("wlrctl pointer click left") end,
  click_right = function() return Hypr.exec("wlrctl pointer click right") end,
  click_middle = function() return Hypr.exec("wlrctl pointer click middle") end,
}

--- Cursor movement factory for Direction.speed_binds / Direction.omni_binds.
--- @param amount number  Pixels to move per axis per trigger
--- @return DirActions
Cursor.move = function(amount)
  return {
    left = Hypr.exec("wlrctl pointer move -" .. amount .. " 0"),
    right = Hypr.exec("wlrctl pointer move " .. amount .. " 0"),
    up = Hypr.exec("wlrctl pointer move 0 -" .. amount),
    down = Hypr.exec("wlrctl pointer move 0 " .. amount),
    nw = Hypr.exec("wlrctl pointer move -" .. amount .. " -" .. amount),
    ne = Hypr.exec("wlrctl pointer move " .. amount .. " -" .. amount),
    sw = Hypr.exec("wlrctl pointer move -" .. amount .. " " .. amount),
    se = Hypr.exec("wlrctl pointer move " .. amount .. " " .. amount),
  }
end

--- Scroll action factory. Returns up/down/left/right actions at the given step size.
--- @param step number
--- @return { up: fun(), down: fun(), left: fun(), right: fun() }
Cursor.scroll = function(step)
  return {
    up = Hypr.exec("wlrctl pointer scroll " .. step .. " 0"),
    down = Hypr.exec("wlrctl pointer scroll -" .. step .. " 0"),
    left = Hypr.exec("wlrctl pointer scroll 0 -" .. step),
    right = Hypr.exec("wlrctl pointer scroll 0 " .. step),
  }
end

local hold_timers = {}

--- Cancel the repeat started by Cursor.hold.
Cursor.hold_stop = function()
  for _, timer in ipairs(hold_timers) do
    timer:set_enabled(false)
  end
  hold_timers = {}
end

--- Repeat `fn` while its key stays down, until Cursor.hold_stop runs on the key's release.
--- A binding's own `repeating` flag cannot do this for scrolling: Hyprland drops the key repeat as soon as an
--- axis event arrives, so wlrctl's first scroll ends it. The keyboard's repeat delay and rate are mirrored.
--- @param fn fun()
--- @return fun()
Cursor.hold = function(fn)
  return function()
    Cursor.hold_stop()
    fn()
    local delay = hl.get_config("input.repeat_delay") or 600
    local rate = hl.get_config("input.repeat_rate") or 25
    local start = hl.timer(
      function() hold_timers[#hold_timers + 1] = hl.timer(fn, { timeout = math.floor(1000 / rate), type = "repeat" }) end,
      { timeout = delay, type = "oneshot" }
    )
    hold_timers[#hold_timers + 1] = start
  end
end

--- Run a wl-kbptr mode.
--- opts.exit = false: exit submap raw, run wl-kbptr, return to Cursor when done (default).
--- opts.exit = true:  run wl-kbptr then exit submap via Submap.reset().
--- @param mode string
--- @param opts? { exit: boolean }
--- @return fun()
Cursor.kbptr = function(mode, opts)
  local cmd = assert(KBPTR_CMDS[mode], "unknown kbptr mode: " .. mode)
  if opts and opts.exit then
    return function()
      Cursor.hold_stop()
      Submap.reset()
      Hypr.cmd_then_dispatch(cmd, 'hl.dsp.submap("reset")')()
    end
  end

  -- Leaves the submap without exit_cursor, so the scroll key's release bind would never fire.
  return function()
    Cursor.hold_stop()
    hl.dispatch(hl.dsp.submap("reset"))
    Hypr.cmd_then_dispatch(cmd, 'hl.dsp.submap("Cursor")')()
  end
end

--- Send a key shortcut to the active window via hyprctl sendshortcut.
--- @param key string  Key name, e.g. "LEFT", "prior", "next"
--- @return fun()
Cursor.send_key = function(key) return Hypr.send(key) end

return Cursor
