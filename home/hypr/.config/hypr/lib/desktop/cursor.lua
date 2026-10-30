--- Cursor control: pointer movement, scrolling, clicking, key dispatch via wlrctl/hyprctl.

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
  floating_r_click = KBPTR .. " -o modes=floating -o mode_floating.source=detect && wlrctl pointer click right",
  tile_click = KBPTR .. " -o modes=tile,click",
  tile_move = KBPTR .. " -o modes=tile",
  tile_r_click = KBPTR .. " -o modes=tile && wlrctl pointer click right",
  split_click = KBPTR .. " -o modes=split,click",
  split_move = KBPTR .. " -o modes=split",
  split_r_click = KBPTR .. " -o modes=split && wlrctl pointer click right",
}

--- Gap between stopping the move timers and starting a click. Every wlrctl step is its own async process, so the
--- start order of a move and the click after it is not their run order under load. This gap lets moves already
--- started run first. It bounds the race and does not remove it.
local CLICK_DELAY_MS = 20

local move_timers = {}

--- @param timers table[]
local function stop_timers(timers)
  for _, timer in ipairs(timers) do
    timer:set_enabled(false)
  end
end

--- Return an action that stops the held-move timers, then clicks `button` after CLICK_DELAY_MS.
--- @param button string
--- @return fun(): fun()
local function click_after_moves(button)
  local click = Hypr.exec("wlrctl pointer click " .. button)
  return function()
    return function()
      stop_timers(move_timers)
      move_timers = {}
      hl.timer(click, { timeout = CLICK_DELAY_MS, type = "oneshot" })
    end
  end
end

--- @class CursorActions
local Cursor = {
  click_left = click_after_moves("left"),
  click_right = click_after_moves("right"),
  click_middle = click_after_moves("middle"),
}

--- Return an action that moves the pointer by (dx, dy) with wlrctl.
--- Not hl.dsp.cursor.move: Hyprland's warp skips focus-follows-mouse, while wlrctl sends real pointer motion. wlrctl
--- adds and removes a virtual pointer on each run, which on Hyprland 0.57 cancels every bind's own repeat, so held
--- moves repeat on Lua timers (Cursor.move_press) instead.
--- @param dx number
--- @param dy number
--- @return fun()
local function move_by(dx, dy) return Hypr.exec("wlrctl pointer move " .. dx .. " " .. dy) end

--- Cursor movement factory for Direction.speed_binds / Direction.omni_binds.
--- @param amount number  Pixels to move per axis per trigger
--- @return DirActions
Cursor.move = function(amount)
  return {
    left = move_by(-amount, 0),
    right = move_by(amount, 0),
    up = move_by(0, -amount),
    down = move_by(0, amount),
    nw = move_by(-amount, -amount),
    ne = move_by(amount, -amount),
    sw = move_by(-amount, amount),
    se = move_by(amount, amount),
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

--- Start `fn` repeating at the keyboard's repeat delay and rate; returns the timers that drive it.
--- @param fn fun()
--- @return table[]
local function start_repeat(fn)
  local delay = hl.get_config("input.repeat_delay") or 600
  local rate = hl.get_config("input.repeat_rate") or 25
  local timers = {}
  timers[1] = hl.timer(
    function() timers[#timers + 1] = hl.timer(fn, { timeout = math.floor(1000 / rate), type = "repeat" }) end,
    { timeout = delay, type = "oneshot" }
  )
  return timers
end

local scroll_timers = {}

--- Cancel the repeat started by Cursor.hold.
Cursor.scroll_stop = function()
  stop_timers(scroll_timers)
  scroll_timers = {}
end

--- Repeat `fn` while its key stays down, until Cursor.scroll_stop runs on the key's release.
--- A binding's own `repeating` flag cannot do this for scrolling: Hyprland drops the key repeat as soon as an
--- axis event arrives, so wlrctl's first scroll ends it.
--- @param fn fun()
--- @return fun()
Cursor.hold = function(fn)
  return function()
    Cursor.scroll_stop()
    fn()
    scroll_timers = start_repeat(fn)
  end
end

--- Unit steps per direction; the held directions move the pointer by the sum of their steps times their amounts.
local UNIT_STEP = {
  left = { -1, 0 },
  right = { 1, 0 },
  up = { 0, -1 },
  down = { 0, 1 },
  nw = { -1, -1 },
  ne = { 1, -1 },
  sw = { -1, 1 },
  se = { 1, 1 },
}

--- @type table<string, number> direction -> pixels per step, for each direction key held down
local held_moves = {}

local function step_held_moves()
  local dx, dy = 0, 0
  for dir, amount in pairs(held_moves) do
    dx = dx + UNIT_STEP[dir][1] * amount
    dy = dy + UNIT_STEP[dir][2] * amount
  end
  if dx ~= 0 or dy ~= 0 then move_by(dx, dy)() end
end

--- Mark a direction held, step once and keep stepping until Cursor.move_release lets go of every held direction.
--- Not the bind's own `repeating` flag: on Hyprland 0.57 a key that starts a chord (H of H+K) fires on release and
--- never repeats, so diagonals come from holding two directions at once instead of from chord binds.
--- @param dir string  A UNIT_STEP key
--- @param amount number
Cursor.move_press = function(dir, amount)
  held_moves[dir] = amount
  stop_timers(move_timers)
  step_held_moves()
  move_timers = start_repeat(step_held_moves)
end

--- @param dir string  A UNIT_STEP key
Cursor.move_release = function(dir)
  held_moves[dir] = nil
  if next(held_moves) ~= nil then return end
  stop_timers(move_timers)
  move_timers = {}
end

--- Stop every held move and scroll. A release that never arrives (the submap left mid-hold) must not keep them going.
Cursor.hold_stop = function()
  Cursor.scroll_stop()
  held_moves = {}
  stop_timers(move_timers)
  move_timers = {}
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
