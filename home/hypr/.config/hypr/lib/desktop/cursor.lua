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

--- Keyboard drag and drop. The button is held with ydotool, because wlrctl has no button down or up. ydotoold is a user
--- daemon on a socket under XDG_RUNTIME_DIR that lives from the grab to the release, and its uinput device going away
--- releases the button even when the button-up is lost. wl-kbptr cancels a drag when it takes keyboard focus (tested by
--- hand), so a pick never overlaps a held button: the picker runs with the button up, then the button goes down at the
--- item and glides to the picked spot.
---
--- phase: idle | picking (picker open, button up) | starting (daemon coming up) | manual | gliding | releasing (button
--- up, the session script still cleaning up: a new drag would share its socket and pid file, so it waits).
--- Callbacks from shell scripts carry the session id, so one that arrives after its session ended is ignored.
local DRAG = {
  THRESHOLD_PX = 8, -- the nudge after the press that gets past a toolkit's drag threshold
  GLIDE_STEPS = 12,
  GLIDE_STEP_MS = 25, -- 12 steps: about 300 ms to the target
  SETTLE_MS = 60, -- lets the last async glide step land before the exact warp
  ARM_MS = 400, -- focus changes this soon after the press come from the press itself
  WATCHDOG_MS = 30000,
  RELEASE_BACKSTOP_MS = 3000,
}
local drag = { phase = "idle", session = 0, timers = {} }

--- Cursor.drag_touch, defined with the rest of the drag code; moves call it.
local drag_touch = function() end

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
  drag_touch() -- the repeat timer calls this too, so a key held past the watchdog's 30 s keeps the drag alive
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
      if drag.phase ~= "idle" then return Cursor.drag_notice("Drop or cancel the drag first") end
      Cursor.hold_stop()
      Submap.reset()
      Hypr.cmd_then_dispatch(cmd, 'hl.dsp.submap("reset")')()
    end
  end

  -- Leaves the submap without exit_cursor, so the scroll key's release bind would never fire.
  return function()
    if drag.phase ~= "idle" then return Cursor.drag_notice("Drop or cancel the drag first") end
    Cursor.hold_stop()
    hl.dispatch(hl.dsp.submap("reset"))
    Hypr.cmd_then_dispatch(cmd, 'hl.dsp.submap("Cursor")')()
  end
end

--- @param text string
--- @return string
local function sh_quote(text) return "'" .. text:gsub("'", "'\\''") .. "'" end

--- Show a notice. Public so the drag tests and the kbptr guard share it.
--- @param text string
Cursor.drag_notice = function(text) hl.dispatch(hl.dsp.exec_cmd("notify-send 'Cursor drag' " .. sh_quote(text))) end

--- @return string|nil
local function drag_socket()
  local dir = os.getenv("XDG_RUNTIME_DIR")
  return dir and dir ~= "" and (dir .. "/hypr-cursor-drag.sock") or nil
end

--- A shell command that calls back into this module once its script reaches that point.
--- @param name string
--- @param id integer
--- @return string
local function callback(name, id)
  return string.format([[hyprctl eval 'require("lib.desktop.cursor").%s(%d)' >/dev/null]], name, id)
end

--- Shell function: stop the process a pid file names, only if it is still a ydotoold. A stale file (the session script
--- died, the pid went to another program) must not get an unrelated process killed.
local STOP_DAEMON = [[stop_daemon() { [ "$(cat "/proc/$1/comm" 2>/dev/null)" = ydotoold ] && kill "$1"; }]]

--- The script that owns one session's daemon: start it, press, report ready, then wait for it to exit and say so.
--- @param id integer
--- @param sock string
--- @return string
local function session_script(id, sock)
  return string.format(
    [[sock=%s; pidf="$sock.pid"
fail() { rm -f "$sock" "$pidf"; notify-send 'Cursor drag' "$1"; %s; exit 1; }
command -v ydotool >/dev/null 2>&1 && command -v ydotoold >/dev/null 2>&1 || fail 'Drag needs ydotool'
rm -f "$sock"
ydotoold --socket-path="$sock" --socket-perm=0600 >/dev/null 2>&1 &
dpid=$!
echo $dpid >"$pidf"
n=0; until [ -S "$sock" ] || [ $n -ge 40 ]; do sleep 0.05; n=$((n+1)); done
if [ ! -S "$sock" ]; then kill $dpid 2>/dev/null; wait $dpid 2>/dev/null; fail 'ydotoold did not start (it needs write access to /dev/uinput: the input group)'; fi
if ! YDOTOOL_SOCKET="$sock" ydotool click 0x40 >/dev/null 2>&1; then kill $dpid 2>/dev/null; wait $dpid 2>/dev/null; fail 'Drag could not press the button'; fi
%s
wait $dpid
rm -f "$sock" "$pidf"
%s]],
    sh_quote(sock),
    callback("drag_failed", id),
    callback("drag_ready", id),
    callback("drag_gone", id)
  )
end

--- The script that ends a session: a 1 px wiggle onto the drop spot (drop only), then button up, then the daemon goes.
--- No pid file means no daemon, so nothing is held. Cancel sends no Escape key: ydotoold's keyboard goes through
--- Hyprland's binds, so the Cursor submap's own Esc bind would catch it and leave the submap.
--- @param sock string
--- @param how "drop"|"cancel"|"abort"
--- @return string
local function release_script(sock, how)
  local before = how == "drop" and "wlrctl pointer move 1 0; wlrctl pointer move -1 0; sleep 0.05; " or ""
  return string.format(
    [[sock=%s; pidf="$sock.pid"; export YDOTOOL_SOCKET="$sock"
%s
[ -f "$pidf" ] || exit 0
%sydotool click 0x80; sleep 0.05
stop_daemon "$(cat "$pidf")"]],
    sh_quote(sock),
    STOP_DAEMON,
    before
  )
end

local function run_shell(script) hl.dispatch(hl.dsp.exec_cmd("sh -c " .. sh_quote(script))) end

local function drag_stop_timers()
  stop_timers(drag.timers)
  drag.timers = {}
  if drag.watchdog then drag.watchdog:set_enabled(false) end
  drag.watchdog = nil
end

--- @return { x: integer, y: integer }|nil
local function pointer_pos()
  local pos = hl.get_cursor_pos and hl.get_cursor_pos()
  if type(pos) ~= "table" or not pos.x or not pos.y then return nil end
  return { x = math.floor(pos.x + 0.5), y = math.floor(pos.y + 0.5) }
end

local function warp_to(pos) hl.dispatch(hl.dsp.cursor.move({ x = pos.x, y = pos.y })) end

--- @param delay integer
--- @param fn fun()
local function drag_after(delay, fn) drag.timers[#drag.timers + 1] = hl.timer(fn, { timeout = delay, type = "oneshot" }) end

--- The one release path. Every way a drag ends comes here. `how` is "drop", "cancel" (pointer back to the grab point
--- first) or "abort" (a plain button-up, for focus loss).
--- @param how "drop"|"cancel"|"abort"
--- @param why? string  Shown in a notice when the user did not ask for the end
--- @return boolean ended
local function drag_end(how, why)
  local phase = drag.phase
  if phase == "idle" or phase == "releasing" then return false end
  local sock = drag.sock
  drag_stop_timers()
  if phase == "picking" then
    drag.phase = "idle"
  elseif phase == "starting" then
    -- The press has not happened, or it is on its way: drag_ready sees `abort` and ends the session.
    drag.abort = how
    if sock then
      run_shell(
        string.format([[pidf=%s.pid; %s; [ -f "$pidf" ] && stop_daemon "$(cat "$pidf")"]], sh_quote(sock), STOP_DAEMON)
      )
    end
  else
    if how == "cancel" and drag.origin then warp_to(drag.origin) end
    run_shell(release_script(sock, how))
    -- Busy until the session script's `gone` callback: its cleanup removes the socket and pid file, which a drag
    -- started now would be using. The timer is a backstop for a lost callback.
    drag.phase = "releasing"
    drag_after(DRAG.RELEASE_BACKSTOP_MS, function() drag.phase = "idle" end)
  end
  if why then Cursor.drag_notice(why) end
  return true
end

--- Re-arm the 30 s watchdog; a drag that is moving is not stuck.
local function arm_watchdog()
  if drag.watchdog then drag.watchdog:set_enabled(false) end
  drag.watchdog = hl.timer(
    function() drag_end("cancel", "Drag cancelled after 30 s") end,
    { timeout = DRAG.WATCHDOG_MS, type = "oneshot" }
  )
end

drag_touch = function()
  if drag.phase == "manual" or drag.phase == "gliding" then arm_watchdog() end
end

--- @return boolean
Cursor.drag_active = function() return drag.phase ~= "idle" and drag.phase ~= "releasing" end

--- Bring a session's daemon up and press at the pointer. `after` says what drag_ready does next.
--- @param after "manual"|"glide"
--- @return boolean started
local function drag_press(after)
  local sock = drag_socket()
  if not sock then
    Cursor.drag_notice("Drag needs XDG_RUNTIME_DIR")
    return false
  end
  drag.session = drag.session + 1
  drag.phase = "starting"
  drag.after = after
  drag.abort = nil
  drag.sock = sock
  arm_watchdog()
  run_shell(session_script(drag.session, sock))
  return true
end

--- Callback: the daemon is up and the button is down.
--- @param id integer
Cursor.drag_ready = function(id)
  if id ~= drag.session or drag.phase ~= "starting" then return end
  if drag.abort then
    local how = drag.abort
    drag.phase = "manual"
    drag_end(how)
    return
  end
  move_by(DRAG.THRESHOLD_PX, 0)()
  drag_after(DRAG.ARM_MS, function() drag.armed = true end)
  drag.armed = false
  if drag.after == "manual" then
    drag.phase = "manual"
    return
  end

  drag.phase = "gliding"
  local from, to = drag.origin, drag.target
  local dx = to.x - from.x - DRAG.THRESHOLD_PX
  local dy = to.y - from.y
  local step, done = 0, { x = 0, y = 0 }
  local timer
  timer = hl.timer(function()
    step = step + 1
    local want_x = math.floor(dx * step / DRAG.GLIDE_STEPS + 0.5)
    local want_y = math.floor(dy * step / DRAG.GLIDE_STEPS + 0.5)
    if want_x ~= done.x or want_y ~= done.y then move_by(want_x - done.x, want_y - done.y)() end
    done.x, done.y = want_x, want_y
    if step < DRAG.GLIDE_STEPS then return end
    timer:set_enabled(false)
    drag_after(DRAG.SETTLE_MS, function()
      warp_to(to)
      drag_end("drop")
    end)
  end, { timeout = DRAG.GLIDE_STEP_MS, type = "repeat" })
  drag.timers[#drag.timers + 1] = timer
end

--- Callback: the session could not start. The script already showed the notice and removed its files.
--- @param id integer
Cursor.drag_failed = function(id)
  if id ~= drag.session or drag.phase == "idle" then return end
  drag_stop_timers()
  drag.phase = "idle"
end

--- Callback: the daemon exited and the session script has cleaned up. Its device is gone, so the button is up; only
--- the state is left to clear.
--- @param id integer
Cursor.drag_gone = function(id)
  if id ~= drag.session or drag.phase == "idle" then return end
  local ended_by_us = drag.phase == "releasing" or drag.abort ~= nil
  drag_stop_timers()
  drag.phase = "idle"
  if not ended_by_us then Cursor.drag_notice("Drag ended: ydotoold exited") end
end

--- Callback: the pick-only wl-kbptr run printed a spot (it warped the pointer there). Warp back to the item and press.
--- @param id integer
Cursor.drag_picked = function(id)
  if id ~= drag.session or drag.phase ~= "picking" then return end
  local target = pointer_pos()
  if not target then
    drag.phase = "idle"
    return Cursor.drag_notice("Drag could not read the picked spot")
  end
  drag.target = target
  warp_to(drag.origin)
  if not drag_press("glide") then drag.phase = "idle" end
end

--- Callback: the picker was dismissed or failed. Nothing was pressed.
--- @param id integer
Cursor.drag_pick_cancelled = function(id)
  if id ~= drag.session or drag.phase ~= "picking" then return end
  drag.phase = "idle"
end

--- Start a drag. `mode` "manual" presses now and HJKL does the moving; "find", "tile" and "split" pick the target with
--- the matching pick-only wl-kbptr mode first, then glide there.
--- @param mode "manual"|"find"|"tile"|"split"
--- @return fun()
Cursor.drag_start = function(mode)
  local pick_cmd = ({ find = KBPTR_CMDS.floating_move, tile = KBPTR_CMDS.tile_move, split = KBPTR_CMDS.split_move })[mode]
  return function()
    if drag.phase ~= "idle" then return end
    local origin = pointer_pos()
    if not origin then return Cursor.drag_notice("Drag could not read the pointer") end
    drag.origin = origin
    if mode == "manual" then return drag_press("manual") end

    Cursor.hold_stop()
    drag.session = drag.session + 1
    drag.phase = "picking"
    drag.sock = nil
    local back = hl.get_current_submap()
    if back == "" or back == "reset" then back = "Cursor" end
    local id = drag.session
    hl.dispatch(hl.dsp.submap("reset"))
    run_shell(
      pick_cmd
        .. string.format("; rc=$?; hyprctl dispatch 'hl.dsp.submap(%q)' >/dev/null; ", back)
        .. string.format(
          "if [ $rc = 0 ]; then %s; else %s; fi",
          callback("drag_picked", id),
          callback("drag_pick_cancelled", id)
        )
    )
  end
end

--- Drop where the pointer is (Enter). Does nothing without a held button.
Cursor.drag_drop = function()
  -- Not while a picked drag starts or glides: it drops on its own at the target.
  if drag.phase == "manual" or (drag.phase == "starting" and drag.after == "manual") then drag_end("drop") end
end

--- Cancel (Esc): pointer back to the grab point, then release. Also cancels a glide.
Cursor.drag_cancel = function() drag_end("cancel") end

--- The submap is being left (any route): a held button must not outlive it.
Cursor.drag_submap_exit = function() drag_end("cancel", drag.phase ~= "idle" and "Drag cancelled" or nil) end

if hl.on then
  -- Focus moving off the dragged-from window means the drag has lost its target, and a held button on a window the
  -- user did not choose is worse than a lost drag.
  hl.on("window.active", function()
    if drag.armed and (drag.phase == "manual" or drag.phase == "gliding") then
      drag_end("abort", "Drag released: focus changed")
    end
  end)
  -- A reload drops this state while a session script may still hold the button; let go of whatever it left.
  hl.on("config.reloaded", function()
    local sock = drag_socket()
    if drag.phase == "idle" and sock then run_shell(release_script(sock, "abort")) end
  end)
end

--- Send a key shortcut to the active window via hyprctl sendshortcut.
--- @param key string  Key name, e.g. "LEFT", "prior", "next"
--- @return fun()
Cursor.send_key = function(key) return Hypr.send(key) end

return Cursor
