-- The Windows, Cursor, Quick Click, Groups, Move, Resize and Delete submaps now name actions. This compares every bind
-- in them with fixtures/act_stateful_binds.tsv (key, which-key label, flags, what the key does), dumped before the
-- move, under four configs: default, no leader with three monitors, persistent workspaces, and vim_mode off. It then
-- checks what the fixture cannot: the state the actions share (the Windows selection, the Cursor scroll timers) lives
-- across key presses, does not leak out of its submap, and is fresh after a reload; `catchall = "stay"` submaps still
-- swallow unbound keys; and each submap file loads the defs its rows name.
--
--   SHELL=/bin/zsh lua home/hypr/tests/act_stateful.lua          compare with the fixture and run the checks
--   SHELL=/bin/zsh lua home/hypr/tests/act_stateful.lua --dump   print the current binds in the fixture's format
local here = arg[0]:match("^(.*)/[^/]*$") or "."
local Stubs = dofile(here .. "/act_stubs.lua")

-- Three windows: two on workspace 1 (the focused one a firefox) and one on workspace 2. None has a pid, so closing
-- dispatches a plain close, and the kill the Delete submap would send to a pid goes to the recorder below.
local WINDOWS = {
	{ address = "0xa1", class = "firefox", workspace = { id = 1 } },
	{ address = "0xb2", class = "kitty", workspace = { id = 1 } },
	{ address = "0xc3", class = "Firefox", workspace = { id = 2 } },
}
local active = WINDOWS[1]
os.execute = function(cmd)
	Stubs.performed[#Stubs.performed + 1] = "os.execute(" .. cmd .. ")"
end
hl.get_active_window = function()
	return active
end
hl.get_active_workspace = function()
	return { id = 1 }
end
hl.get_windows = function()
	return WINDOWS
end
hl.get_config = function(name)
	return name == "input.repeat_delay" and 600 or 25
end
-- The submap Hyprland reports. The dump runs every row as if pressed inside its own submap, so this defaults to Cursor;
-- the tests of actions called from outside set it to "".
local reported_submap = "Cursor"
hl.get_current_submap = function()
	return reported_submap
end
-- Timers the tests can fire and inspect.
local timers = {}
hl.timer = function(fn, opts)
	local timer = { fn = fn, opts = opts, enabled = true }
	function timer:set_enabled(on)
		self.enabled = on
	end
	timers[#timers + 1] = timer
	return timer
end
local function enabled_timers()
	local count = 0
	for _, timer in ipairs(timers) do
		if timer.enabled then
			count = count + 1
		end
	end
	return count
end

-- The keys that follow Config: persistent workspaces (slots per monitor) and vim_mode off (arrows lead).
table.insert(Stubs.VARIANTS, { name = "persistent", leader = "SUPER", monitors = {}, persistent_workspaces = 3 })
table.insert(Stubs.VARIANTS, { name = "arrows", leader = "SUPER", monitors = {}, vim_mode = false })

local MODULES = {
	"keymaps.global",
	"keymaps.submaps.windows",
	"keymaps.submaps.cursor",
	"keymaps.submaps.groups",
	"keymaps.submaps.move",
	"keymaps.submaps.resize",
	"keymaps.submaps.delete",
}
local SUBMAPS = {
	Windows = true,
	Cursor = true,
	["Quick Click"] = true,
	Groups = true,
	Move = true,
	Resize = true,
	Delete = true,
}
local function in_listed_submap(submap)
	return SUBMAPS[submap] == true
end

if arg[1] == "--dump" then
	print(table.concat(Stubs.dump_lines(MODULES, in_listed_submap), "\n"))
	os.exit(0)
end

local failures = Stubs.compare(MODULES, here .. "/fixtures/act_stateful_binds.tsv", in_listed_submap)
local function check(name, ok)
	if not ok then
		failures = failures + 1
		print("FAIL " .. name)
	end
end

local function load_all()
	timers = {}
	Stubs.load(Stubs.VARIANTS[1], MODULES)
end

--- The bind entry for a key in a submap.
local function bind(submap, key)
	for _, entry in ipairs(Stubs.binds) do
		if entry.submap == submap and entry.key == key then
			return entry
		end
	end
	error("no bind " .. submap .. " " .. key)
end

--- Press a key: run its action, return what it did.
local function press(submap, key)
	Stubs.performed = {}
	local entry = bind(submap, key)
	if type(entry.action) == "function" then
		entry.action()
	else
		hl.dispatch(entry.action)
	end
	return Stubs.performed
end

local function count_of(performed, pattern)
	local count = 0
	for _, text in ipairs(performed) do
		if text:find(pattern, 1, true) then
			count = count + 1
		end
	end
	return count
end

local function text_of(performed)
	return table.concat(performed, ";")
end

-- The ids the rows name exist, nothing warned, and the delete group list matches the performer's.
load_all()
local Act = require("lib.act")
check("no warnings: " .. table.concat(Act.warnings, "; "), #Act.warnings == 0)
local ids = {}
for _, handle in ipairs(Act.list()) do
	ids[handle.id] = handle
end
for _, id in ipairs({
	"windows.select_toggle",
	"windows.swap_selected",
	"windows.move_selected",
	"windows.close_selected",
	"groups.move",
	"move.step",
	"resize.step",
	"resize.reset",
	"cursor.move",
	"cursor.scroll",
	"cursor.scroll_stop",
	"cursor.click",
	"cursor.pointer_mode",
	"delete.close_group",
	"delete.close_workspace",
	"window.kill",
	"window.float_toggle",
}) do
	check("defined: " .. id, ids[id] ~= nil)
end
-- float_toggle moved to defs/windows.lua; running it by id must still reach the float dispatcher.
Stubs.performed = {}
Act.run("window.float_toggle")
check("window.float_toggle runs: " .. text_of(Stubs.performed), count_of(Stubs.performed, "float") == 1)
local listed = {}
for _, param in ipairs(ids["delete.close_group"] and ids["delete.close_group"].params or {}) do
	listed = param.values or listed
end
check(
	"delete.close_group takes every group: " .. table.concat(listed, ","),
	table.concat(listed, ",") == table.concat(require("lib.actions.delete").groups, ",")
)

-- Each submap file loaded alone, without the global keys, names only actions it requires itself.
for _, module in ipairs({
	"keymaps.submaps.windows",
	"keymaps.submaps.cursor",
	"keymaps.submaps.groups",
	"keymaps.submaps.move",
	"keymaps.submaps.resize",
	"keymaps.submaps.delete",
}) do
	timers = {}
	Stubs.load(Stubs.VARIANTS[1], { module })
	local warnings = require("lib.act").warnings
	check(module .. " alone: no warnings: " .. table.concat(warnings, "; "), #warnings == 0)
end

-- A swallowed key: a "stay" submap binds `catchall` to a no-op dispatcher, Delete (a one-shot) to a function.
load_all()
for _, name in ipairs({ "Windows", "Cursor", "Quick Click", "Groups", "Move", "Resize" }) do
	local entry = bind(name, "catchall")
	check(name .. ": catchall stays", type(entry.action) == "table" and entry.action.text == "no_op")
	check(name .. ": catchall releases", entry.opts.release == true and entry.opts.ignore_mods == true)
end
check("Delete: catchall resets", type(bind("Delete", "catchall").action) == "function")

-- The Windows selection survives between presses. Select two windows, then one key acts on both and puts focus back.
load_all()
active = WINDOWS[1]
press("Windows", "SPACE")
active = WINDOWS[2]
local selected = press("Windows", "SPACE")
check("select: highlights the window", count_of(selected, "set_prop") == 2)
local moved = press("Windows", "SHIFT + H")
check("selected move: one move per selected window", count_of(moved, "window.move({direction=l})") == 2)
check(
	"selected move: both windows are focused",
	count_of(moved, "focus({window=address:0xa1})") == 1 and count_of(moved, "focus({window=address:0xb2})") == 2
)
check("selected move: focus ends where it began", moved[#moved] == "focus({window=address:0xb2})")
local floated = press("Windows", "F")
check("selected float: toggles both", count_of(floated, "window.float") == 2)

-- Toggling a selected window again takes it out, so the next key acts on the one left.
active = WINDOWS[2]
press("Windows", "SPACE")
moved = press("Windows", "SHIFT + H")
check("deselect: one window left selected", count_of(moved, "window.move({direction=l})") == 1)
check("deselect: the one left is focused", count_of(moved, "focus({window=address:0xa1})") == 1)

-- Swap uses the selection and clears it; with two selected besides the focused window it refuses.
active = WINDOWS[2]
local swapped = press("Windows", "S")
check("swap: swaps with the selected window", count_of(swapped, "window.swap({target=address:0xa1})") == 1)
moved = press("Windows", "SHIFT + H")
check("swap: clears the selection", count_of(moved, "focus(") == 0 and count_of(moved, "window.move") == 1)

-- Leaving the submap clears the selection; it does not reach the other submaps or the next visit.
active = WINDOWS[1]
press("Windows", "SPACE")
local Submap = require("lib.key.submap")
local left = {}
Stubs.performed = {}
Submap.registry.Windows.on_exit({})
left = Stubs.performed
check("exit: restores the border", count_of(left, "set_prop") == 2)
moved = press("Windows", "SHIFT + H")
check("exit: the next visit starts empty", count_of(moved, "focus(") == 0 and count_of(moved, "window.move") == 1)
active = WINDOWS[1]
press("Windows", "SPACE")
local nudged = press("Move", "H")
check("other submaps ignore the selection", #nudged == 1 and nudged[1]:find("window.move", 1, true) ~= nil)
check("Groups ignores the selection", count_of(press("Groups", "H"), "focus(") == 1)
Submap.registry.Windows.on_exit({})

-- A reload starts from nothing: no duplicate binds or actions, an empty selection.
local function bind_count()
	local counts = {}
	for _, entry in ipairs(Stubs.binds) do
		counts[entry.submap] = (counts[entry.submap] or 0) + 1
	end
	return counts
end
active = WINDOWS[1]
press("Windows", "SPACE")
local first = bind_count()
load_all()
local second = bind_count()
local same = true
for name, count in pairs(first) do
	same = same and second[name] == count
end
check("reload: the same binds, none twice", same)
check("reload: no warnings", #require("lib.act").warnings == 0)
check("reload: the selection is empty", count_of(press("Windows", "SHIFT + H"), "focus(") == 0)

-- Cursor scrolling: each press stops the repeat the last one started, so held timers do not pile up, and a release row
-- (or leaving the submap) stops what is left.
load_all()
local scroll = press("Cursor", "E")
check("scroll: the first step fires at once", text_of(scroll) == "exec_cmd(wlrctl pointer scroll 10 0)")
check("scroll: one timer waits for the repeat delay", enabled_timers() == 1 and timers[#timers].opts.timeout == 600)
press("Cursor", "E")
press("Cursor", "SHIFT + E")
check("scroll: a press stops the previous repeat", enabled_timers() == 1)
-- Fire the delay timer that is still enabled: it starts the repeating one.
for _, timer in ipairs(timers) do
	if timer.enabled then
		timer.fn()
	end
end
check("scroll: the repeat runs beside the delay timer", enabled_timers() == 2)
local fast = press("Cursor", "SHIFT + Y")
check("scroll: a new press carries its own step", text_of(fast) == "exec_cmd(wlrctl pointer scroll -100 0)")
check("scroll: it replaced both", enabled_timers() == 1)
press("Cursor", "Y")
for _, timer in ipairs(timers) do
	if timer.enabled then
		timer.fn()
	end
end
check("scroll: repeating before the release", enabled_timers() == 2)
local released = 0
for _, entry in ipairs(Stubs.binds) do
	if entry.submap == "Cursor" and entry.opts.release == true and entry.opts.ignore_mods == true then
		if entry.key ~= "catchall" then
			released = released + 1
		end
	end
end
check("scroll: four release rows", released == 4)
for _, entry in ipairs(Stubs.binds) do
	if entry.submap == "Cursor" and entry.key == "E" and entry.opts.release then
		entry.action()
	end
end
check("scroll: release stops every timer", enabled_timers() == 0)
press("Cursor", "E")
check("scroll: a press after a release starts again", enabled_timers() == 1)
Stubs.performed = {}
Submap.registry.Cursor.on_exit({})
check("scroll: leaving the submap stops the repeat", enabled_timers() == 0)
check("scroll: leaving kills wl-kbptr", count_of(Stubs.performed, "pkill wl-kbptr") == 1)

-- Pointer moves carry their step and direction; a click can leave the submap.
check("pointer: diagonal chord", text_of(press("Cursor", "SHIFT + H+K")) == "exec_cmd(wlrctl pointer move -100 -100)")
check("pointer: click stays", text_of(press("Cursor", "SPACE")) == "exec_cmd(wlrctl pointer click left)")
check(
	"pointer: click with exit resets",
	text_of(press("Cursor", "CTRL + SPACE")) == "exec_cmd(wlrctl pointer click left);submap(reset)"
)

-- Called from outside the Cursor submap (hypr-act, the bar, voice), nothing is left running for a release row that
-- cannot fire: a scroll is one step with no timers, and a pointer mode leaves the submap path instead of entering Cursor.
load_all()
reported_submap = ""
Stubs.performed = {}
timers = {}
require("lib.act").run("cursor.scroll", "down", 10)
check("outside Cursor: scroll is one step", text_of(Stubs.performed) == "exec_cmd(wlrctl pointer scroll -10 0)")
check("outside Cursor: scroll starts no timer", enabled_timers() == 0)
Stubs.performed = {}
require("lib.act").run("cursor.pointer_mode", "floating_click")
check(
	"outside Cursor: pointer mode never enters Cursor",
	count_of(Stubs.performed, 'submap("Cursor")') == 0 and count_of(Stubs.performed, "submap(reset)") >= 1
)
reported_submap = "Cursor"
Stubs.performed = {}
require("lib.act").run("cursor.pointer_mode", "floating_click")
check("inside Cursor: pointer mode returns to Cursor", count_of(Stubs.performed, 'submap("Cursor")') == 1)
timers = {}
require("lib.act").run("cursor.scroll", "down", 10)
check("inside Cursor: scroll repeats", enabled_timers() == 1)
require("lib.act").run("cursor.scroll_stop")

-- A selection made from outside the Windows submap is gone when the submap is entered.
load_all()
active = WINDOWS[1]
require("lib.act").run("windows.select_toggle")
Stubs.performed = {}
require("lib.key.submap").registry.Windows.on_enter({})
check("enter Windows: clears a selection made outside", count_of(Stubs.performed, "set_prop") == 2)
check("enter Windows: the first key acts on the focused window", count_of(press("Windows", "SHIFT + H"), "focus(") == 0)

-- A selected window that closed is forgotten before the next action, so nothing hits the focused window by mistake.
load_all()
active = WINDOWS[1]
press("Windows", "SPACE")
active = WINDOWS[2]
press("Windows", "SPACE")
local gone = table.remove(WINDOWS, 1)
moved = press("Windows", "SHIFT + H")
check("closed selected window: only the open one is acted on", count_of(moved, "window.move({direction=l})") == 1)
check("closed selected window: it is never focused", count_of(moved, "address:0xa1") == 0)
active = WINDOWS[1]
check("closed selected window: swap refuses", count_of(press("Windows", "S"), "window.swap") == 0)
table.remove(WINDOWS, 1)
moved = press("Windows", "SHIFT + H")
check("every selected window closed: acts on the focused one", count_of(moved, "focus(") == 0)
table.insert(WINDOWS, 1, gone)

-- four step sizes on the direction keys, held keys repeat
load_all()
for _, name in ipairs({ "Move", "Resize" }) do
	local sizes = {}
	for _, key in ipairs({ "H", "SHIFT + H", "CTRL + H", "CTRL + SHIFT + H" }) do
		local entry = bind(name, key)
		check(name .. ": " .. key .. " repeats", entry.opts.repeating == true)
		sizes[#sizes + 1] = text_of(press(name, key))
	end
	local steps = {}
	for index, text in ipairs(sizes) do
		steps[index] = math.abs(tonumber(text:match("x=(-?%d+)")) or 0)
	end
	local bare, shift, ctrl, ctrl_shift = steps[1], steps[2], steps[3], steps[4]
	check(
		name .. ": CTRL finest < bare < SHIFT < CTRL + SHIFT: " .. table.concat(steps, ","),
		ctrl > 0 and ctrl < bare and bare < shift and shift < ctrl_shift
	)
end

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("act stateful: all passed")
