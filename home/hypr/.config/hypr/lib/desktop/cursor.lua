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
--- daemon on a socket under XDG_RUNTIME_DIR that lives for a visit to the Cursor or Quick Click submap: it starts on
--- entry and stops on every exit, so a drag never pays for its start. It is warm because Hyprland registers the uinput
--- virtual mouse some time after the daemon's socket appears, and a press sent before that is lost; the first press
--- waits until `hyprctl devices` lists it. The daemon's device going away releases the button even when the button-up is
--- lost. wl-kbptr cancels a drag when it takes keyboard focus (tested by hand), so a pick never overlaps a held button:
--- the picker runs with the button up, then the button goes down at the item and glides to the picked spot.
---
--- Each daemon is an instance with its own directory under XDG_RUNTIME_DIR/hypr-cursor-drag, named by this config
--- load's token and a counter, so no script, old or new, can touch another instance's socket or pid file. A reload
--- stops the instances of every earlier load (see config.reloaded).
--- daemon.state: down | starting (not yet in `hyprctl devices`) | ready | stopping (its script still cleaning up: a
--- second daemon would list a second virtual mouse of the same name, so the next one waits).
--- drag.phase: idle | picking (picker open, button up) | starting (waiting for the daemon, or the press is on its way) |
--- manual | gliding | releasing (button-up on its way: a new drag waits).
--- Callbacks from shell scripts carry the instance or drag id, which includes the load token, so one that arrives after
--- its daemon or drag ended, even from before a reload, is ignored.
local DRAG = {
  THRESHOLD_PX = 8, -- the nudge after the press that gets past a toolkit's drag threshold
  GLIDE_STEPS = 12,
  GLIDE_STEP_MS = 25, -- 12 steps: about 300 ms to the target
  SETTLE_MS = 60, -- lets the last async glide step land before the exact warp
  ARM_MS = 400, -- focus changes this soon after the press come from the press itself
  WATCHDOG_TICKS = 30, -- seconds without a move
  RELEASE_BACKSTOP_MS = 3000,
  PRESS_PAUSE_MS = 100, -- the app sees the press before any motion
}
--- Unique per config load. A counter alone restarts at 0 on reload, so an old script's callback could name a new
--- daemon or drag.
--- @return string
local function load_token()
  local file = io.open("/proc/sys/kernel/random/uuid")
  local uuid = file and file:read("l")
  if file then file:close() end
  if uuid and uuid:match("^[%x-]+$") then return uuid end
  return string.format("%d-%x", os.time(), math.floor(os.clock() * 1e6))
end
local LOAD = load_token()

local drag = { phase = "idle", session = 0, id = "", timers = {} }
local daemon = { state = "down", gen = 0, id = "" }

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

--- The parent of every daemon instance's directory.
--- @return string|nil
local function drag_base()
  local dir = os.getenv("XDG_RUNTIME_DIR")
  return dir and dir ~= "" and (dir .. "/hypr-cursor-drag") or nil
end

--- A shell command that calls back into this module once its script reaches that point.
--- @param name string
--- @param id string  A daemon instance or drag id; only [%w-] characters, so it needs no quoting
--- @return string
local function callback(name, id)
  return string.format([[hyprctl eval 'require("lib.desktop.cursor").%s("%s")' >/dev/null]], name, id)
end

--- Shell function: stop the process a pid file names, only if it is still a ydotoold. A stale file (the session script
--- died, the pid went to another program) must not get an unrelated process killed.
local STOP_DAEMON = [[stop_daemon() { [ "$(cat "/proc/$1/comm" 2>/dev/null)" = ydotoold ] && kill "$1"; }]]

--- jq filters over `hyprctl devices -j`. Hyprland renames devices to keep names unique: the keyboard of ydotoold is
--- "ydotoold-virtual-device" and its mouse "ydotoold-virtual-device-1", with a suffix that varies. So the wait does not
--- look for a name. It looks for a ydotoold mouse missing from the list taken before the start, which also keeps another
--- daemon's mouse (a ydotool service, a daemon still going away) from counting as this one. `strings` drops a null name.
local MICE_BEFORE = [=[[.mice[]?.name | strings]]=]
local NEW_YDOTOOLD_MOUSE =
  [=[[.mice[]?.name | strings | select(ascii_downcase | startswith("ydotoold")) | select(IN($before[]) | not)] | length > 0]=]

--- The script that owns one daemon instance: start it, wait until Hyprland lists its virtual mouse, report ready, then
--- wait for it to exit, remove the instance's directory and say so. A failure reports its reason through
--- `daemon_failed`. Both waits end early once the daemon is dead, so a stopped daemon's script ends at once.
--- @param id string
--- @param dir string
--- @return string
local function daemon_script(id, dir)
  return string.format(
    [[dir=%s; sock="$dir/sock"; pidf="$dir/pid"; mice_before=%s; new_mouse=%s
fail() { rm -rf "$dir"; hyprctl eval "require('lib.desktop.cursor').daemon_failed('%s', '$1')" >/dev/null; exit 1; }
seen() { hyprctl devices -j 2>/dev/null | jq -e --argjson before "$before" "$new_mouse" >/dev/null 2>&1; }
command -v ydotool >/dev/null 2>&1 && command -v ydotoold >/dev/null 2>&1 || fail 'Drag needs ydotool'
command -v jq >/dev/null 2>&1 || fail 'Drag needs jq'
mkdir -p -m 700 "$dir" || fail 'Drag could not create its runtime directory'
before=$(hyprctl devices -j 2>/dev/null | jq -c "$mice_before" 2>/dev/null)
[ -n "$before" ] || before='[]'
ydotoold --socket-path="$sock" --socket-perm=0600 >/dev/null 2>&1 &
dpid=$!
echo $dpid >"$pidf"
alive() { kill -0 $dpid 2>/dev/null; }
n=0; until [ -S "$sock" ] || ! alive || [ $n -ge 40 ]; do sleep 0.05; n=$((n+1)); done
if [ ! -S "$sock" ]; then kill $dpid 2>/dev/null; wait $dpid 2>/dev/null; fail 'ydotoold did not start. It needs write access to /dev/uinput: install.sh installs the udev rule 70-dotfiles-uinput.rules and applies it'; fi
n=0; until seen || ! alive || [ $n -ge 100 ]; do sleep 0.05; n=$((n+1)); done
alive || fail 'ydotoold exited'
if ! seen; then kill $dpid 2>/dev/null; wait $dpid 2>/dev/null; fail 'Hyprland did not list the ydotoold virtual mouse'; fi
%s
wait $dpid
rm -rf "$dir"
%s]],
    sh_quote(dir),
    sh_quote(MICE_BEFORE),
    sh_quote(NEW_YDOTOOLD_MOUSE),
    id,
    callback("daemon_ready", id),
    callback("daemon_gone", id)
  )
end

--- The script that presses the button at the pointer once the daemon is ready.
--- @param id string
--- @param dir string
--- @return string
local function press_script(id, dir)
  return string.format(
    [[if YDOTOOL_SOCKET=%s ydotool click 0x40 >/dev/null 2>&1; then %s; else %s; fi]],
    sh_quote(dir .. "/sock"),
    callback("drag_ready", id),
    callback("drag_failed", id)
  )
end

--- The shell line that stops the daemon a pid file names. No pid file means no daemon.
--- @return string
local STOP_LINE = [[[ -f "$pidf" ] && stop_daemon "$(cat "$pidf")"]]

--- The script that stops one instance's daemon. Its own script removes the files once the daemon is gone.
--- @param dir string
--- @return string
local function stop_script(dir)
  return string.format([[pidf=%s; %s; %s]], sh_quote(dir .. "/pid"), STOP_DAEMON, STOP_LINE)
end

--- The script a reload runs: for every instance directory of an earlier load, let go of the button its daemon may hold,
--- stop that daemon and remove the directory. This load's own instances are skipped, so one already started survives.
--- @param base string
--- @return string
local function reload_cleanup_script(base)
  return string.format(
    [[base=%s; %s
for dir in "$base"/*/; do
  dir=${dir%%/}; [ -d "$dir" ] || continue
  case ${dir##*/} in %s-*) continue ;; esac
  pidf="$dir/pid"
  if [ -f "$pidf" ] && [ "$(cat "/proc/$(cat "$pidf")/comm" 2>/dev/null)" = ydotoold ]; then
    YDOTOOL_SOCKET="$dir/sock" ydotool click 0x80; sleep 0.05
  fi
  %s
  rm -rf "$dir"
done]],
    sh_quote(base),
    STOP_DAEMON,
    LOAD,
    STOP_LINE
  )
end

--- The script that ends a drag: a 1 px wiggle onto the drop spot (drop only), then button up, then `drag_released`. With
--- `stop`, the daemon goes after the button-up. No pid file means no daemon, so nothing is held. Cancel sends no Escape
--- key: ydotoold's keyboard goes through Hyprland's binds, so the Cursor submap's own Esc bind would catch it and leave
--- the submap.
--- @param dir string  The instance that pressed
--- @param how "drop"|"cancel"|"abort"
--- @param id string
--- @param stop? boolean
--- @return string
local function release_script(dir, how, id, stop)
  local before = how == "drop" and "wlrctl pointer move 1 0; wlrctl pointer move -1 0; sleep 0.05; " or ""
  return string.format(
    [[dir=%s; pidf="$dir/pid"; export YDOTOOL_SOCKET="$dir/sock"
%s
if [ -f "$pidf" ]; then
%sydotool click 0x80; sleep 0.05
%s
fi
%s]],
    sh_quote(dir),
    STOP_DAEMON,
    before,
    stop and STOP_LINE or "",
    callback("drag_released", id)
  )
end

local function run_shell(script) hl.dispatch(hl.dsp.exec_cmd("sh -c " .. sh_quote(script))) end

local function drag_stop_timers()
  stop_timers(drag.timers)
  drag.timers = {}
  if drag.watchdog then drag.watchdog:set_enabled(false) end
  drag.watchdog = nil
end

--- Start a daemon instance for this submap visit, or note that one is wanted once the old one has finished stopping.
--- Does nothing while one is starting or ready.
local function daemon_start()
  if daemon.state == "stopping" then
    daemon.want = true
    return
  end
  if daemon.state ~= "down" then return end
  local base = drag_base()
  if not base then return end
  daemon.gen = daemon.gen + 1
  daemon.id = LOAD .. "-" .. daemon.gen
  daemon.dir = base .. "/" .. daemon.id
  daemon.state = "starting"
  run_shell(daemon_script(daemon.id, daemon.dir))
end

--- The instance is gone (or never came up): start the one a re-entered submap asked for meanwhile.
local function daemon_down()
  daemon.state = "down"
  if daemon.want then
    daemon.want = false
    daemon_start()
  end
end

--- Stop the daemon by pid with a /proc check. `with_release` is true when a release script for this instance already
--- carries the stop.
--- @param with_release? boolean
local function daemon_stop(with_release)
  daemon.want = false
  if daemon.state == "down" or daemon.state == "stopping" then return end
  daemon.state = "stopping"
  -- If the script's `gone` callback is lost, nothing else would end this state.
  local id = daemon.id
  hl.timer(function()
    if daemon.id == id and daemon.state == "stopping" then daemon_down() end
  end, { timeout = DRAG.RELEASE_BACKSTOP_MS, type = "oneshot" })
  if not with_release then run_shell(stop_script(daemon.dir)) end
end

--- @return { x: integer, y: integer }|nil
local function pointer_pos()
  local pos = hl.get_cursor_pos and hl.get_cursor_pos()
  if type(pos) ~= "table" or not pos.x or not pos.y then return nil end
  return { x = math.floor(pos.x + 0.5), y = math.floor(pos.y + 0.5) }
end

local function warp_to(pos) hl.dispatch(hl.dsp.cursor.move({ x = pos.x, y = pos.y })) end

--- A new drag gets an id no earlier drag of any load had, so a late callback of an old one is ignored.
local function new_drag_id()
  drag.session = drag.session + 1
  drag.id = LOAD .. "-" .. drag.session
end

--- @param delay integer
--- @param fn fun()
local function drag_after(delay, fn) drag.timers[#drag.timers + 1] = hl.timer(fn, { timeout = delay, type = "oneshot" }) end

--- The only way back to idle. It runs what a drop asked for once the release is over (the exit click leaves the submap
--- here), so a stored request never outlives its drag.
local function drag_idle()
  local on_done = drag.on_done
  drag.on_done = nil
  drag.phase = "idle"
  if on_done then on_done() end
end

--- The one release path. Every way a drag ends comes here. `how` is "drop", "cancel" (pointer back to the grab point
--- first) or "abort" (a plain button-up, for focus loss).
--- @param how "drop"|"cancel"|"abort"
--- @param why? string  Shown in a notice when the user did not ask for the end
--- @param stop? boolean  The submap visit is over: the daemon stops after the button-up
--- @return boolean ended
local function drag_end(how, why, stop)
  local phase = drag.phase
  if phase == "idle" or phase == "releasing" then
    if stop then daemon_stop() end
    return false
  end
  local dir = drag.dir
  drag_stop_timers()
  if phase == "picking" or (phase == "starting" and not drag.pressing) then
    -- Nothing is pressed.
    drag_idle()
    if stop then daemon_stop() end
  elseif phase == "starting" then
    -- The press is on its way: drag_ready sees `abort` and releases.
    drag.abort = how
    -- If both of the press script's callbacks are lost, nothing else would end this phase.
    drag_after(DRAG.RELEASE_BACKSTOP_MS, function()
      run_shell(release_script(dir, "abort", drag.id))
      drag_idle()
    end)
    if stop then daemon_stop() end
  else
    if how == "cancel" and drag.origin then warp_to(drag.origin) end
    run_shell(release_script(dir, how, drag.id, stop))
    if stop then daemon_stop(dir == daemon.dir) end
    -- Busy until the script's `drag_released` callback, so a drag started now cannot press before the button-up. The
    -- timer is a backstop for a lost callback.
    drag.phase = "releasing"
    drag_after(DRAG.RELEASE_BACKSTOP_MS, drag_idle)
  end
  if why then Cursor.drag_notice(why) end
  return true
end

--- Start the watchdog: one timer for the whole drag that ticks every second and ends the drag after WATCHDOG_TICKS
--- ticks with no move. Not a timer re-created per move: Hyprland 0.57 keeps a disabled timer, and a held key moves
--- about 25 times a second.
local function start_watchdog()
  drag.idle_ticks = 0
  drag.watchdog = hl.timer(function()
    drag.idle_ticks = drag.idle_ticks + 1
    if drag.idle_ticks >= DRAG.WATCHDOG_TICKS then drag_end("cancel", "Drag cancelled after 30 s") end
  end, { timeout = 1000, type = "repeat" })
end

--- A drag that is moving is not stuck.
drag_touch = function() drag.idle_ticks = 0 end

--- A full click would let go of the button the app sees held, so right and middle clicks wait for the drag to end. A
--- left click drops instead (see the click action), so it never gets here during a drag.
--- @return boolean blocked
Cursor.drag_blocks_click = function()
  if drag.phase == "idle" then return false end
  Cursor.drag_notice("Drop or cancel the drag first")
  return true
end

--- Whether a drag, in any phase, is using the left button.
--- @return boolean
Cursor.drag_busy = function() return drag.phase ~= "idle" end

--- @return boolean
Cursor.drag_active = function() return drag.phase ~= "idle" and drag.phase ~= "releasing" end

--- Send the press once the daemon is ready. The drag keeps the instance it pressed with, for the release.
local function drag_send_press()
  drag.pressing = true
  drag.dir = daemon.dir
  run_shell(press_script(drag.id, drag.dir))
end

--- Press at the pointer, or wait for the daemon to be ready first (starting it if the visit has none). `after` says what
--- drag_ready does next.
--- @param after "manual"|"glide"
--- @return boolean started
local function drag_press(after)
  if not drag_base() then
    Cursor.drag_notice("Drag needs XDG_RUNTIME_DIR")
    return false
  end
  new_drag_id()
  drag.phase = "starting"
  drag.after = after
  drag.abort = nil
  drag.dir = nil
  drag.pressing = false
  start_watchdog()
  if daemon.state == "ready" then
    drag_send_press()
  else
    daemon_start()
  end
  return true
end

--- Callback: the daemon is up and Hyprland lists its virtual mouse.
--- @param id string
Cursor.daemon_ready = function(id)
  if id ~= daemon.id or daemon.state ~= "starting" then return end
  daemon.state = "ready"
  if drag.phase == "starting" and not drag.pressing then drag_send_press() end
end

--- Callback: the daemon could not start, or was stopped before it was ready. The script already removed its files.
--- @param id string
--- @param why string
Cursor.daemon_failed = function(id, why)
  if id ~= daemon.id then return end
  local was = daemon.state
  -- A drag waiting through a stop is served by the daemon the re-entered submap wants, so only a failed start ends it.
  -- Entering the submap starts the daemon without a drag asking, so only a waiting drag is told.
  if was == "starting" and drag.phase == "starting" and not drag.pressing then
    drag_stop_timers()
    drag_idle()
    Cursor.drag_notice(why)
  end
  daemon_down()
end

--- Callback: the daemon exited and its script has cleaned up. Its device is gone, so the button is up.
--- @param id string
Cursor.daemon_gone = function(id)
  if id ~= daemon.id then return end
  local was = daemon.state
  if was ~= "stopping" and drag.phase ~= "idle" then
    local released = drag.phase == "releasing" or drag.abort ~= nil
    drag_stop_timers()
    if not released then Cursor.drag_notice("Drag ended: ydotoold exited") end
    drag_idle()
  end
  daemon_down()
end

--- Callback: the button is up.
--- @param id string
Cursor.drag_released = function(id)
  if id ~= drag.id or drag.phase ~= "releasing" then return end
  drag_stop_timers()
  drag_idle()
end

--- Callback: the press is done, the button is down.
--- @param id string
Cursor.drag_ready = function(id)
  if id ~= drag.id or drag.phase ~= "starting" then return end
  if drag.abort then
    local how = drag.abort
    drag.abort = nil
    drag.phase = "manual"
    drag_end(how)
    return
  end
  drag_after(DRAG.ARM_MS, function() drag.armed = true end)
  drag.armed = false
  if drag.after == "manual" then
    drag.phase = "manual"
    drag_after(DRAG.PRESS_PAUSE_MS, function() move_by(DRAG.THRESHOLD_PX, 0)() end)
    return
  end

  drag.phase = "gliding"
  local from, to = drag.origin, drag.target
  local dx = to.x - from.x - DRAG.THRESHOLD_PX
  local dy = to.y - from.y
  local step, done = 0, { x = 0, y = 0 }
  local timer
  drag_after(DRAG.PRESS_PAUSE_MS, function()
    move_by(DRAG.THRESHOLD_PX, 0)()
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
  end)
end

--- Callback: the press failed (the daemon is most likely gone).
--- @param id string
Cursor.drag_failed = function(id)
  if id ~= drag.id or drag.phase == "idle" then return end
  drag_stop_timers()
  drag_idle()
  Cursor.drag_notice("Drag could not press the button")
end

--- Callback: the pick-only wl-kbptr run printed a spot (it warped the pointer there). Warp back to the item and press.
--- @param id string
Cursor.drag_picked = function(id)
  if id ~= drag.id or drag.phase ~= "picking" then return end
  local target = pointer_pos()
  if not target then
    drag_idle()
    return Cursor.drag_notice("Drag could not read the picked spot")
  end
  drag.target = target
  warp_to(drag.origin)
  if not drag_press("glide") then drag_idle() end
end

--- Callback: the picker was dismissed or failed. Nothing was pressed.
--- @param id string
Cursor.drag_pick_cancelled = function(id)
  if id ~= drag.id or drag.phase ~= "picking" then return end
  drag_idle()
end

--- Whether a drag may start or end here. A drag lives inside one visit to a Cursor-family submap, whose exit hook is
--- what lets go of the button and stops the daemon. A call from anywhere else (hypr-act, the bar, voice) would have no
--- hook to end it. Hyprland's own submap decides, as for the other Cursor actions (see in_cursor_submap in
--- lib/act/defs/cursor.lua).
--- @return boolean
local function drag_allowed()
  local live = hl.get_current_submap()
  if live == "Cursor" or live == "Quick Click" then return true end
  Cursor.drag_notice("Drag works only in the Cursor submap or Quick Click")
  return false
end

--- Start a drag. `mode` "manual" presses now and HJKL does the moving; "find", "tile" and "split" pick the target with
--- the matching pick-only wl-kbptr mode first, then glide there.
--- @param mode "manual"|"find"|"tile"|"split"
--- @return fun()
Cursor.drag_start = function(mode)
  local pick_cmd = ({ find = KBPTR_CMDS.floating_move, tile = KBPTR_CMDS.tile_move, split = KBPTR_CMDS.split_move })[mode]
  return function()
    if not drag_allowed() or drag.phase ~= "idle" then return end
    local origin = pointer_pos()
    if not origin then return Cursor.drag_notice("Drag could not read the pointer") end
    drag.origin = origin
    if mode == "manual" then return drag_press("manual") end

    Cursor.hold_stop()
    new_drag_id()
    drag.phase = "picking"
    drag.dir = nil
    local back = hl.get_current_submap()
    local id = drag.id
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

--- Drop where the pointer is (the left-click key). Does nothing without a held button. `on_done` runs once the release
--- has finished, which is later than this call.
--- @param on_done? fun()
--- @return boolean dropped
Cursor.drag_drop = function(on_done)
  if not drag_allowed() then return false end
  -- Not while a picked drag starts or glides: it drops on its own at the target.
  if drag.phase == "manual" or (drag.phase == "starting" and drag.after == "manual") then
    drag.on_done = on_done
    return drag_end("drop")
  end
  return false
end

--- Cancel (Esc): pointer back to the grab point, then release. Also cancels a glide.
Cursor.drag_cancel = function()
  if drag_allowed() then drag_end("cancel") end
end

--- A submap is being left (any route): a held button must not outlive it. The daemon stays only when the next submap
--- is the other Cursor-family one.
--- @param to? string  The submap being entered
Cursor.drag_submap_exit = function(to)
  local keep = to == "Cursor" or to == "Quick Click"
  drag_end("cancel", Cursor.drag_active() and "Drag cancelled" or nil, not keep)
end

--- A Cursor-family submap was entered: start the daemon if the visit has none.
Cursor.daemon_start = daemon_start

if hl.on then
  -- Focus moving off the dragged-from window means the drag has lost its target, and a held button on a window the
  -- user did not choose is worse than a lost drag.
  hl.on("window.active", function()
    if drag.armed and (drag.phase == "manual" or drag.phase == "gliding") then
      drag_end("abort", "Drag released: focus changed")
    end
  end)
  -- A reload drops this state while an earlier load's daemon may still hold the button; let go of whatever it left.
  hl.on("config.reloaded", function()
    local base = drag_base()
    if base then run_shell(reload_cleanup_script(base)) end
  end)
end

--- Send a key shortcut to the active window via hyprctl sendshortcut.
--- @param key string  Key name, e.g. "LEFT", "prior", "next"
--- @return fun()
Cursor.send_key = function(key) return Hypr.send(key) end

return Cursor
