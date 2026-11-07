-- Lifecycle check for keyboard drag and drop (lib/desktop/cursor.lua). It runs the real shell scripts the module
-- builds against stub ydotool, ydotoold, wlrctl, hyprctl, notify-send and kbptr.sh set up by cursor-drag.sh, on a
-- virtual clock for the module's timers. Each scenario ends by asserting that no daemon, pid file or Lua state is left.
--
--   home/hypr/tests/cursor-drag.sh
local here = arg[0]:match("^(.*)/[^/]*$") or "."
local Stubs = dofile(here .. "/act_stubs.lua")
local work = assert(os.getenv("DRAG_TEST_DIR"), "run through cursor-drag.sh")
local stub = work .. "/stub"
local run_dir = os.getenv("XDG_RUNTIME_DIR")
local pidfile = run_dir .. "/hypr-cursor-drag.sock.pid"

local failures = 0
local function check(ok, what)
	if not ok then
		failures = failures + 1
		print("FAIL " .. what)
	end
end

local function sleep(secs)
	os.execute("sleep " .. secs)
end

local function read_file(path)
	local file = io.open(path)
	if not file then
		return ""
	end
	local text = file:read("a")
	file:close()
	return text
end

local function write_file(path, text)
	local file = assert(io.open(path, "w"))
	file:write(text)
	file:close()
end

local function log()
	return read_file(stub .. "/log")
end

local function count(pattern)
	local n = 0
	for line in log():gmatch("[^\n]+") do
		if line:find("^" .. pattern) then
			n = n + 1
		end
	end
	return n
end

--- Index of the first log line containing the text, or nil; for order checks.
local function line_of(pattern)
	local n = 0
	for line in log():gmatch("[^\n]+") do
		n = n + 1
		if line:find(pattern, 1, true) then
			return n
		end
	end
end

-- hl: shell commands run for real in the stub sandbox; the rest is recorded or virtual.
local clock, timers, handlers = 0, {}, {}
local pointer_reads = math.huge -- reads left before the pointer position goes unreadable
local function pointer()
	local x, y = read_file(stub .. "/pointer"):match("(%-?%d+)%s+(%-?%d+)")
	return tonumber(x), tonumber(y)
end
local function set_pointer(x, y)
	write_file(stub .. "/pointer", x .. " " .. y .. "\n")
end

local function shell_quote(text)
	return "'" .. text:gsub("'", "'\\''") .. "'"
end

local base_dispatch = hl.dispatch
local submap_calls = {}
hl.dispatch = function(dispatcher)
	base_dispatch(dispatcher)
	local text = dispatcher.text
	local cmd = text:match("^exec_cmd%((.*)%)$")
	if cmd then
		-- Not run in the foreground: a session script waits on its daemon for the whole drag.
		os.execute(
			"env -i PATH="
				.. stub
				.. "/bin:"
				.. stub
				.. " HOME="
				.. os.getenv("HOME")
				.. " XDG_RUNTIME_DIR="
				.. run_dir
				.. " STUB_DIR="
				.. stub
				.. " sh -c "
				.. shell_quote(cmd)
				.. " >/dev/null 2>&1 &"
		)
		return
	end
	local x, y = text:match("^cursor%.move%(%{x=(%-?%d+),y=(%-?%d+)%}%)$")
	if x then
		set_pointer(x, y)
		return
	end
	local name = text:match("^submap%((.*)%)$")
	if name then
		submap_calls[#submap_calls + 1] = name
	end
end
hl.get_cursor_pos = function()
	pointer_reads = pointer_reads - 1
	if pointer_reads < 0 then
		return nil
	end
	local x, y = pointer()
	return { x = x or 100, y = y or 100 }
end
local current_submap = "Cursor"
hl.get_current_submap = function()
	return current_submap
end
hl.timer = function(fn, opts)
	local timer = { fn = fn, opts = opts, enabled = true, due = clock + opts.timeout }
	function timer:set_enabled(on)
		self.enabled = on
	end
	timers[#timers + 1] = timer
	return timer
end
hl.on = function(event, fn)
	handlers[event] = fn
end

--- Move the virtual clock forward, running every timer that comes due, in order. Shell callbacks are pumped between.
local pump
local function advance(ms)
	local target = clock + ms
	while true do
		local next_timer
		for _, timer in ipairs(timers) do
			if timer.enabled and timer.due <= target and (not next_timer or timer.due < next_timer.due) then
				next_timer = timer
			end
		end
		if not next_timer then
			break
		end
		clock = math.max(clock, next_timer.due)
		if next_timer.opts.type == "repeat" then
			next_timer.due = clock + next_timer.opts.timeout
		else
			next_timer.enabled = false
		end
		next_timer.fn()
	end
	clock = target
end

--- Run the hyprctl eval callbacks the scripts queued (what Hyprland would run).
pump = function()
	os.rename(stub .. "/cb.queue", stub .. "/cb.work")
	for line in read_file(stub .. "/cb.work"):gmatch("[^\n]+") do
		local fn, err = load(line)
		check(fn, "callback loads: " .. line .. " " .. tostring(err))
		if fn then
			fn()
		end
	end
	os.remove(stub .. "/cb.work")
end

--- Pump callbacks until `cond` holds or `secs` pass.
local function settle(cond, secs)
	local deadline = os.time() + (secs or 5)
	repeat
		pump()
		if cond() then
			return true
		end
		sleep(0.03)
	until os.time() > deadline
	pump()
	return cond()
end

local function daemons_running()
	return os.execute("pgrep -f '" .. run_dir .. "/hypr-cursor-drag[.]sock' >/dev/null 2>&1") == true
end

local Cursor, Submap, binds_by

--- Load the keymaps fresh: a new Cursor module, state idle, binds registered.
local function fresh(mode, keep_session)
	for _, timer in ipairs(timers) do
		timer.enabled = false
	end
	timers, handlers, submap_calls = {}, {}, {}
	write_file(stub .. "/mode", mode or "")
	if not keep_session then
		write_file(stub .. "/log", "")
		os.remove(stub .. "/cb.queue")
		os.remove(pidfile)
		os.remove(run_dir .. "/hypr-cursor-drag.sock")
		set_pointer(100, 100)
	end
	pointer_reads = math.huge
	current_submap = "Cursor"
	Stubs.load({ name = "default", leader = "SUPER", monitors = {} }, { "keymaps.submaps.cursor" })
	Cursor = require("lib.desktop.cursor")
	Submap = require("lib.key.submap")
	binds_by = {}
	for _, entry in ipairs(Stubs.binds) do
		binds_by[entry.submap .. "|" .. entry.key] = entry
	end
	Submap.current = "Cursor"
end

local function press(key, submap)
	local entry = binds_by[(submap or "Cursor") .. "|" .. key]
	assert(entry, "no bind " .. key)
	if type(entry.action) == "function" then
		entry.action()
	else
		hl.dispatch(entry.action)
	end
end

--- After a scenario: nothing may be left, in Lua or on the machine.
local function assert_clean(name)
	check(
		settle(function()
			return not Cursor.drag_active()
		end, 3),
		name .. ": Lua state is idle"
	)
	check(
		settle(function()
			return not daemons_running()
		end, 3),
		name .. ": no daemon process left"
	)
	check(read_file(pidfile) == "", name .. ": no pid file left")
	check(
		count("ydotool click 0x40") <= count("ydotool click 0x80")
			or count("ydotoold stop") >= 1
			or count("ydotool click 0x40") == 0,
		name .. ": a press has a release or the daemon's end"
	)
end

local function ready()
	return settle(function()
		return count("ydotool click 0x40") >= 1 and count("wlrctl pointer move 8 0") >= 1
	end)
end

--- 1. ydotool missing: a notice and nothing else.
fresh()
local ydotool_stub = read_file(stub .. "/ydotool")
os.remove(stub .. "/ydotool")
press("V")
settle(function()
	return count("notify") >= 1
end)
check(log():find("Drag needs ydotool", 1, true), "missing ydotool: notice shown")
check(count("ydotool ") == 0 and count("ydotoold start") == 0, "missing ydotool: no click, no daemon")
assert_clean("missing ydotool")
write_file(stub .. "/ydotool", ydotool_stub)
os.execute("chmod +x " .. stub .. "/ydotool")

--- 2. Manual drag: V grabs, Enter drops.
fresh()
press("V")
check(ready(), "manual: grab presses and nudges")
check(Cursor.drag_active(), "manual: active after grab")
press("V")
press("SHIFT + V")
check(count("ydotool click 0x40") == 1 and count("ydotoold start") == 1, "double V: one daemon, one press")
press("RETURN")
check(
	settle(function()
		return count("ydotool click 0x80") == 1
	end),
	"manual: Enter releases the button"
)
check(
	settle(function()
		return count("ydotoold stop") == 1
	end),
	"manual: Enter stops the daemon"
)
check(count("wlrctl pointer move 1 0") == 1, "manual: drop wiggles onto the spot")
check(line_of("ydotool click 0x40") < line_of("ydotool click 0x80"), "manual: press before release")
check(count("ydotool key") == 0, "manual: a drop sends no Escape")
assert_clean("manual")

--- 3. Enter and Esc with no drag.
fresh()
press("RETURN")
press("ESCAPE")
check(count("ydotool ") == 0 and count("ydotoold") == 0, "no drag: Enter and Esc touch nothing")
check(submap_calls[#submap_calls] == "reset", "no drag: Esc leaves the submap")
assert_clean("no drag")

--- 4. Cancel: back to the grab point, then release; no Escape key (the submap's own Esc bind would catch it) and the
--- submap stays open.
fresh()
press("V")
ready()
set_pointer(300, 250)
submap_calls = {}
press("ESCAPE")
check(
	settle(function()
		return count("ydotool click 0x80") == 1
	end),
	"cancel: releases"
)
local px, py = pointer()
check(px == 100 and py == 100, "cancel: pointer back at the grab point")
check(count("ydotool key") == 0, "cancel: no Escape key is sent")
check(#submap_calls == 0, "cancel: submap stays open")
check(
	settle(function()
		return count("ydotoold stop") == 1
	end),
	"cancel: daemon stopped"
)
assert_clean("cancel")

--- 5. Daemon fails to start.
fresh("DAEMON=exit")
press("V")
check(
	settle(function()
		return log():find("ydotoold did not start", 1, true) ~= nil
	end),
	"daemon exits: notice"
)
check(count("ydotool click") == 0, "daemon exits: no click")
assert_clean("daemon exits")

--- 6. Socket never appears: the wait gives up, kills the daemon, tells the user.
fresh("DAEMON=nosocket")
press("V")
check(
	settle(function()
		return log():find("ydotoold did not start", 1, true) ~= nil
	end, 6),
	"no socket: notice after the wait"
)
check(count("ydotool click") == 0, "no socket: no click")
check(count("ydotoold stop") == 1, "no socket: daemon killed")
assert_clean("no socket")

--- 7. The press fails.
fresh("FAIL_PRESS=1")
press("V")
check(
	settle(function()
		return log():find("could not press", 1, true) ~= nil
	end),
	"press fails: notice"
)
check(
	settle(function()
		return count("ydotoold stop") == 1
	end),
	"press fails: daemon killed"
)
assert_clean("press fails")

--- 8. Watchdog, and a move resetting it.
fresh()
press("V")
ready()
advance(29000)
Cursor.move_press("left", 5)
Cursor.move_release("left")
advance(29000)
check(Cursor.drag_active() and count("ydotool click 0x80") == 0, "watchdog: a move resets it")
advance(1500)
check(
	settle(function()
		return count("ydotool click 0x80") == 1
	end),
	"watchdog: fires and releases"
)
check(log():find("cancelled after 30 s", 1, true), "watchdog: notice")
assert_clean("watchdog")

--- 9. Submap exit mid-drag (Leader reset, any route to Submap.reset).
fresh()
press("V")
ready()
Submap.reset()
check(
	settle(function()
		return count("ydotool click 0x80") == 1
	end),
	"submap exit: releases"
)
check(settle(function()
	return count("ydotoold stop") == 1
end) and count("ydotool key") == 0, "submap exit: cancels and stops the daemon")
assert_clean("submap exit")

--- 10. wl-kbptr mid-drag is refused; the drag survives.
fresh()
press("V")
ready()
Cursor.kbptr("tile_click")()
Cursor.kbptr("tile_click", { exit = true })()
sleep(0.2)
check(count("kbptr") == 0, "kbptr mid-drag: picker never opens")
check(Cursor.drag_active() and count("ydotool click 0x80") == 0, "kbptr mid-drag: drag survives")
check(log():find("Drop or cancel the drag first", 1, true), "kbptr mid-drag: notice")
Cursor.hold_stop()
check(Cursor.drag_active(), "hold_stop does not release")
press("RETURN")
settle(function()
	return count("ydotool click 0x80") == 1
end)
assert_clean("kbptr mid-drag")

--- 11. Pick flow, picker dismissed: nothing presses.
fresh("PICK=dismiss")
press("SHIFT + V")
check(
	settle(function()
		return line_of('hl.dsp.submap("Cursor")') ~= nil or log():find("hl.dsp.submap", 1, true) ~= nil
	end),
	"dismissed picker: submap restored"
)
sleep(0.2)
pump()
check(count("ydotool ") == 0 and count("ydotoold start") == 0, "dismissed picker: no press, no daemon")
check(count("kbptr %-o modes=floating") == 1, "dismissed picker: find mode ran")
assert_clean("dismissed picker")

--- 12. Pick flow, picker returns a spot: back to the item, press, glide, exact warp, release.
fresh('PICK="400 300"')
press("CTRL + V")
check(
	settle(function()
		return count("ydotool click 0x40") == 1
	end),
	"pick: presses after the picker"
)
check(count("kbptr %-o modes=tile") == 1, "pick: tile mode ran")
check(
	settle(function()
		return count("wlrctl pointer move 8 0") == 1
	end),
	"pick: threshold nudge"
)
for _ = 1, 20 do
	advance(30)
	sleep(0.01)
end
advance(100)
check(
	settle(function()
		return count("ydotool click 0x80") == 1
	end),
	"pick: releases after the glide"
)
local gx, gy = pointer()
check(gx == 400 and gy == 300, "pick: ends exactly on the target")
local sum_x, sum_y = 0, 0
for dx, dy in log():gmatch("wlrctl pointer move (%-?%d+) (%-?%d+)") do
	sum_x, sum_y = sum_x + tonumber(dx), sum_y + tonumber(dy)
end
check(sum_x == 300 and sum_y == 200, "pick: glide covers the distance (" .. sum_x .. "," .. sum_y .. ")")
check(count("wlrctl pointer move") >= 8, "pick: glide is stepped")
assert_clean("pick")

--- 13. Pick flow, no position readable after the pick.
fresh('PICK="400 300"')
pointer_reads = 1 -- the grab point reads; the picked spot does not
press("ALT + V")
settle(function()
	return log():find("could not read the picked spot", 1, true) ~= nil
end)
check(log():find("could not read the picked spot", 1, true), "no position: notice")
check(count("ydotool ") == 0, "no position: no press")
assert_clean("no position")

--- 14. Glide interrupted by Esc (and Enter ignored while gliding).
fresh('PICK="400 300"')
press("SHIFT + V")
settle(function()
	return count("wlrctl pointer move 8 0") == 1
end)
advance(80)
press("RETURN")
check(count("ydotool click 0x80") == 0, "glide: Enter does not drop")
press("ESCAPE")
check(
	settle(function()
		return count("ydotool click 0x80") == 1
	end),
	"glide: Esc releases"
)
local moves_then = count("wlrctl pointer move")
advance(1000)
check(count("wlrctl pointer move") == moves_then, "glide: no step after Esc")
local cx, cy = pointer()
check(cx == 100 and cy == 100, "glide: pointer back at the item")
check(count("ydotool key") == 0, "glide: no Escape key")
assert_clean("glide cancel")

--- 15. ydotoold killed from outside mid-drag: no stuck state, and a new drag works.
fresh()
press("V")
ready()
os.execute('kill "$(cat ' .. shell_quote(pidfile) .. ')"')
check(
	settle(function()
		return not Cursor.drag_active()
	end),
	"external kill: Lua state clears"
)
check(
	settle(function()
		return log():find("ydotoold exited", 1, true) ~= nil
	end),
	"external kill: notice"
)
advance(40000)
check(count("ydotool click 0x80") == 0, "external kill: the watchdog is gone")
press("V")
check(ready() and Cursor.drag_active(), "external kill: a new drag starts")
press("RETURN")
settle(function()
	return count("ydotool click 0x80") == 1
end)
assert_clean("external kill")

--- 16. Focus loss releases (once armed), without an Escape.
fresh()
press("V")
ready()
handlers["window.active"]()
check(count("ydotool click 0x80") == 0, "focus: the press's own focus change is ignored")
advance(500)
handlers["window.active"]()
check(
	settle(function()
		return count("ydotool click 0x80") == 1
	end),
	"focus: loss releases"
)
check(count("ydotool key") == 0, "focus: no Escape to the new window")
assert_clean("focus loss")

--- 17. A reload leaves a session script holding the button: the new config lets go.
fresh()
press("V")
ready()
fresh("", true) -- a new Lua state with the old session script still running
write_file(stub .. "/log", "")
handlers["config.reloaded"]()
check(
	settle(function()
		return count("ydotool click 0x80") == 1
	end),
	"reload: the leftover button is released"
)
check(
	settle(function()
		return count("ydotoold stop") == 1
	end),
	"reload: the leftover daemon is stopped"
)
assert_clean("reload")

--- 18. Quick Click carries the pick variants, Enter and the escape, and no plain V.
fresh("PICK=dismiss")
check(
	binds_by["Quick Click|SHIFT + V"] and binds_by["Quick Click|CTRL + V"] and binds_by["Quick Click|ALT + V"],
	"quick click: pick rows"
)
check(binds_by["Quick Click|RETURN"] and not binds_by["Quick Click|V"], "quick click: Enter, and no manual V")
press("SHIFT + V", "Quick Click")
settle(function()
	return count("kbptr") == 1
end)
check(count("kbptr") == 1, "quick click: find drag runs")
assert_clean("quick click")

--- 19. A direction key held past 30 s keeps the drag alive: the watchdog is for idle drags, and the held key's
--- repeat timer is what moves the pointer.
fresh()
press("V")
ready()
Cursor.move_press("left", 1)
advance(31000)
check(Cursor.drag_active() and count("ydotool click 0x80") == 0, "held key: the repeat refreshes the watchdog")
Cursor.move_release("left")
press("RETURN")
settle(function()
	return count("ydotool click 0x80") == 1
end)
assert_clean("held key")

--- 20. XDG_RUNTIME_DIR gone when the pick returns: back to idle, with a notice.
fresh('PICK="400 300"')
local real_getenv = os.getenv
os.getenv = function(name)
	if name == "XDG_RUNTIME_DIR" then
		return nil
	end
	return real_getenv(name)
end
press("SHIFT + V")
check(
	settle(function()
		return log():find("XDG_RUNTIME_DIR", 1, true) ~= nil
	end),
	"no runtime dir: notice"
)
check(
	settle(function()
		return not Cursor.drag_active()
	end),
	"no runtime dir: back to idle"
)
os.getenv = real_getenv
check(count("ydotool ") == 0, "no runtime dir: no press")

--- 21. A new drag right after a drop waits for the old session's cleanup, so it cannot share its socket and pid file.
fresh()
press("V")
ready()
press("RETURN")
press("V")
check(count("ydotoold start") == 1, "fast regrab: ignored while the old session cleans up")
check(
	settle(function()
		return count("ydotoold stop") == 1
	end),
	"fast regrab: old daemon stopped"
)
check(
	settle(function()
		press("V") -- ignored until the `gone` callback ends the release
		return count("ydotoold start") == 2
	end),
	"fast regrab: allowed once cleanup is done"
)
ready()
press("RETURN")
settle(function()
	return count("ydotool click 0x80") == 2
end)
assert_clean("fast regrab")

--- 22. Enter while a picked drag is still starting does not end it before the glide.
fresh('PICK="400 300"')
press("SHIFT + V")
settle(function()
	return count("ydotoold start") >= 1
end)
press("RETURN")
check(
	settle(function()
		return count("wlrctl pointer move 8 0") == 1
	end),
	"picked drag: Enter while starting is ignored"
)
for _ = 1, 20 do
	advance(30)
	sleep(0.01)
end
advance(100)
settle(function()
	return count("ydotool click 0x80") == 1
end)
local ex, ey = pointer()
check(ex == 400 and ey == 300, "picked drag: still reaches the target")
assert_clean("picked drag Enter")

--- 23. A stale pid file must not get an unrelated process killed (the pid was reused).
fresh()
local bystander = io.popen("sleep 60 >/dev/null 2>&1 & echo $!"):read("n")
write_file(pidfile, bystander .. "\n")
handlers["config.reloaded"]()
sleep(0.5)
check(os.execute("kill -0 " .. bystander) == true, "stale pid: an unrelated process is not killed")
os.execute("kill " .. bystander)
os.remove(pidfile)

--- 24. The Esc bind says what Esc does in each submap.
fresh()
check(binds_by["Cursor|ESCAPE"].opts.desc:find("Cancel", 1, true), "esc label: Cursor says it cancels a drag")

--- 25. A held key makes many move ticks but only one watchdog timer.
fresh()
press("V")
ready()
Cursor.move_press("left", 1)
advance(10000)
local watchdogs = 0
for _, timer in ipairs(timers) do
	if timer.opts.timeout == 1000 and timer.opts.type == "repeat" then
		watchdogs = watchdogs + 1
	end
end
check(watchdogs == 1, "watchdog: one timer however many moves (" .. watchdogs .. ")")
Cursor.move_release("left")
press("RETURN")
settle(function()
	return count("ydotool click 0x80") == 1
end)
assert_clean("one watchdog")

--- 26. Click actions wait for the drag to end: a full click would let go of the button the app sees held.
fresh()
press("V")
ready()
press("SPACE")
press("CTRL + SPACE")
advance(100)
sleep(0.2)
check(count("wlrctl pointer click") == 0, "click: blocked during a drag")
check(log():find("Drop or cancel the drag first", 1, true) ~= nil, "click: notice")
check(#submap_calls == 0, "click: the exit variant does not leave the submap either")
press("RETURN")
settle(function()
	return count("ydotool click 0x80") == 1
end)
settle(function()
	press("SPACE") -- ignored until the release has finished
	advance(100)
	return count("wlrctl pointer click left") >= 1
end)
check(count("wlrctl pointer click left") >= 1, "click: works again after the drag")
assert_clean("click guard")

--- 27. A lost `gone` callback: the 3 s backstop frees the next drag.
fresh()
press("V")
ready()
press("RETURN")
settle(function()
	return count("ydotoold stop") == 1
end)
sleep(0.3)
os.remove(stub .. "/cb.queue") -- the `gone` callback never arrives
pump()
press("V")
check(count("ydotoold start") == 1, "lost gone: still busy before the backstop")
advance(3100)
press("V")
check(
	settle(function()
		return count("ydotoold start") == 2 and count("wlrctl pointer move 8 0") == 2
	end),
	"lost gone: the backstop frees the next drag"
)
press("RETURN")
settle(function()
	return count("ydotool click 0x80") == 2
end)
assert_clean("lost gone")

--- 28. Both callbacks lost while starting (after an abort): the backstop ends the phase.
fresh()
press("V")
settle(function()
	return count("ydotoold start") == 1 and read_file(pidfile) ~= ""
end)
press("RETURN") -- before `ready`: the abort kills the daemon
settle(function()
	return count("ydotoold stop") == 1
end)
sleep(0.3)
os.remove(stub .. "/cb.queue") -- neither `ready` nor `gone` arrives
pump()
advance(3100)
press("V")
check(
	settle(function()
		return count("ydotoold start") == 2
	end),
	"lost ready: the backstop frees the next drag"
)
settle(function()
	return count("wlrctl pointer move 8 0") >= 1
end)
press("RETURN")
settle(function()
	return count("ydotoold stop") == 2
end)
assert_clean("lost ready")

--- 29. Enter then Esc while the release finishes: no false cancel notice.
fresh()
press("V")
ready()
press("RETURN")
press("ESCAPE")
sleep(0.3)
pump()
check(log():find("Drag cancelled", 1, true) == nil, "esc after drop: no cancel notice")
assert_clean("esc after drop")

print(failures == 0 and "cursor drag: all passed" or (failures .. " failed"))
os.exit(failures == 0 and 0 or 1)
