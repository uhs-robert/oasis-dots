-- Loads the global keymaps and the Leader, Applications, Go, System and Bar submaps against a stubbed `hl` under two
-- Config shapes and compares every bind in those submaps with fixtures/act_submap_rows_binds.tsv: key, which-key label,
-- flags and what the key does. The fixture was dumped from the submaps as they were before their rows named actions and
-- is unchanged by that move. It also checks the row form itself ({ key, "id" } and { key, { id, args } }): the label
-- comes from the action unless the row gives one, an unknown id or bad args warn and drop only that row, and rows still
-- exit a one-shot submap or stay in it (`keep`).
--
--   SHELL=/bin/zsh lua home/hypr/tests/act_submap_rows.lua          compare with the fixture
--   SHELL=/bin/zsh lua home/hypr/tests/act_submap_rows.lua --dump   print the current binds in the fixture's format
local here = arg[0]:match("^(.*)/[^/]*$") or "."
local Stubs = dofile(here .. "/act_stubs.lua")

local MODULES = {
	"keymaps.global",
	"keymaps.submaps.leader",
	"keymaps.submaps.apps",
	"keymaps.submaps.go",
	"keymaps.submaps.system",
	"keymaps.submaps.bar",
	"keymaps.submaps.groups", -- entered by a Leader row
}
local SUBMAPS = { Leader = true, Applications = true, Go = true, System = true, Bar = true }
local function in_listed_submap(submap)
	return SUBMAPS[submap] == true
end

if arg[1] == "--dump" then
	print(table.concat(Stubs.dump_lines(MODULES, in_listed_submap), "\n"))
	os.exit(0)
end

local failures = Stubs.compare(MODULES, here .. "/fixtures/act_submap_rows_binds.tsv", in_listed_submap)
local function check(name, ok)
	if not ok then
		failures = failures + 1
		print("FAIL " .. name)
	end
end

-- The action ids the rows name exist and the real tree loads without a warning.
Stubs.load(Stubs.VARIANTS[1], MODULES)
local Act = require("lib.act")
check("no warnings: " .. table.concat(Act.warnings, "; "), #Act.warnings == 0)
local ids = {}
for _, handle in ipairs(Act.list()) do
	ids[handle.id] = handle
end
for _, id in ipairs({
	"popup.open",
	"apps.focus",
	"apps.open",
	"terminal.tool",
	"terminal.editor",
	"workspace.focus_last",
	"system.update",
	"system.edit_keymaps",
}) do
	check("defined: " .. id, ids[id] ~= nil)
end
-- The app names an action takes are exactly the names Apps.map has, so a new app cannot be left out by accident.
local Apps = require("lib.desktop.apps")
local names = {}
for name in pairs(Apps.map) do
	names[#names + 1] = name
end
table.sort(names)
local listed = {}
for _, param in ipairs(ids["apps.focus"] and ids["apps.focus"].params or {}) do
	listed = param.values or {}
end
local sorted_listed = { table.unpack(listed) }
table.sort(sorted_listed)
check(
	"apps.focus takes every Apps.map name: " .. table.concat(sorted_listed, ","),
	table.concat(names, ",") == table.concat(sorted_listed, ",")
)

-- Each submap loaded on its own, without the global keys first, names only actions its file requires.
for _, module in ipairs({ "keymaps.submaps.leader", "keymaps.submaps.apps", "keymaps.submaps.go", "keymaps.submaps.system" }) do
	Stubs.load(Stubs.VARIANTS[1], { module })
	local warnings = require("lib.act").warnings
	check(module .. " alone: no warnings: " .. table.concat(warnings, "; "), #warnings == 0)
end

-- The row form, on its own submap in a fresh load.
local function row_binds(rows, catchall)
	Stubs.load(Stubs.VARIANTS[1], { "keymaps.global", "lib.act.defs.apps" })
	local Submap = require("lib.key.submap")
	Stubs.binds = {}
	Submap.define({ name = "Probe", escape = "reset", catchall = catchall or false, binds = rows }).setup()
	local found = {}
	for _, entry in ipairs(Stubs.binds) do
		if entry.submap == "Probe" then
			found[entry.key] = entry
		end
	end
	return found, require("lib.act")
end

local found, ProbeAct = row_binds({
	{ "A", "terminal.open" },
	{ "B", { "menu.drun" }, "Own Label" },
	{ "C", "terminal.yazi", false },
	{ "D", "no.such_id" },
	{ "E", { "submap.enter", { "Groups" } }, nil, { keep = true } },
	{ "F", { "submap.enter" } },
	{ "G", { "submap.enter", { 3 } } },
	{ "H", "terminal.task_manager" },
	{ "I", { "terminal.tool", { "qalc" } } },
})
check("row: id takes the action's label", found.A and found.A.opts.desc == "Terminal")
check("row: desc overrides the label", found.B and found.B.opts.desc == "Own Label")
-- a row with no description is not listed
check("row: desc = false leaves it undescribed", found.C and found.C.opts.desc == nil)
check("row: unknown id drops only that row", found.D == nil and found.H and found.H.opts.desc == "Task Manager")
check("row: opts reach the bind", found.E and found.E.opts.keep == true and found.E.opts.desc == "Enter Submap")
check("row: missing required arg drops the row", found.F == nil)
check("row: wrong arg type drops the row", found.G == nil)
check("row: each problem warned once", #ProbeAct.warnings == 3)
local text = table.concat(ProbeAct.warnings, "\n")
check("row: warning names the unknown id", text:find("no.such_id", 1, true) ~= nil)
check("row: warning names the missing arg", text:find("needs at least 1", 1, true) ~= nil)

Stubs.performed = {}
found.A.action()
check("row: an id row runs the action", table.concat(Stubs.performed, ";") == "exec_cmd(kitty --single-instance)")
Stubs.performed = {}
found.I.action()
check(
	"row: args reach the action",
	table.concat(Stubs.performed, ";") == "exec_cmd(kitty --single-instance --class bottom-half-screen -e qalc)"
)

-- In a one-shot submap an id row exits after it runs, and `keep` stays; both as plain rows do.
found = row_binds({
	{ "A", "terminal.open" },
	{ "B", { "submap.enter", { "Probe" } }, "Stay", { keep = true } },
}, "reset")
Stubs.performed = {}
found.A.action()
check("row: one-shot exits after an id row", table.concat(Stubs.performed, ";"):find("submap(reset)", 1, true) ~= nil)
Stubs.performed = {}
found.B.action()
check("row: keep stays after an id row", table.concat(Stubs.performed, ";") == "submap(Probe)")

-- The System submap's power rows are the power.confirm action, not a command line of their own, so they need no entry
-- in lib/check/registry.allow. The fixture comparison above already proves the effect is unchanged.
Stubs.load(Stubs.VARIANTS[1], MODULES)
local ran = {}
local PowerAct = require("lib.act")
local real_run = PowerAct.run
PowerAct.run = function(id, ...)
	ran[#ran + 1] = id .. "(" .. table.concat({ ... }, ",") .. ")"
	return real_run(id, ...)
end
for key, kind in pairs({ E = "logout", L = "lock", R = "reboot", P = "poweroff" }) do
	ran = {}
	for _, entry in ipairs(Stubs.binds) do
		if entry.submap == "System" and entry.key == key then
			pcall(entry.action)
		end
	end
	check("power row " .. key .. " runs power.confirm " .. kind, ran[1] == "power.confirm(" .. kind .. ")")
end
PowerAct.run = real_run

-- The submap lifecycle on probe submaps: entry key, ESCAPE, BACKSPACE, unbound-key policies, the which-key toggle.
local function probes(specs, variant)
	Stubs.load(variant or Stubs.VARIANTS[1], { "keymaps.global", "lib.act.defs.apps" })
	local Submap = require("lib.key.submap")
	Stubs.binds = {}
	for _, spec in ipairs(specs) do
		Submap.define(spec).setup()
	end
	return Submap
end

--- The bind for `key` in `submap` ("" is the global map), or nil.
local function probe_bind(submap, key)
	for _, entry in ipairs(Stubs.binds) do
		if entry.submap == submap and entry.key == key then
			return entry
		end
	end
end

local function pressed(submap, key)
	Stubs.performed = {}
	local entry = probe_bind(submap, key)
	if entry == nil then
		return "NO BIND"
	end
	if type(entry.action) == "function" then
		entry.action()
	else
		hl.dispatch(entry.action)
	end
	return table.concat(Stubs.performed, ";")
end

local ROWS = { { "A", "terminal.open" } }

-- the entry key switches into the submap
probes({ { name = "Probe", desc = "+Probe", enter = "SUPER + P", binds = ROWS } })
check("entry key enters the submap", pressed("", "SUPER + P") == "submap(Probe)")
check("entry key is labelled", probe_bind("", "SUPER + P").opts.desc == "+Probe")

-- a leader-based entry key follows the leader, none left behind
Stubs.load(
	{ name = "alt", leader = "ALT", monitors = {} },
	{ "keymaps.global", "keymaps.submaps.leader", "keymaps.submaps.go" }
)
check("leader ALT: Leader entry key", probe_bind("", "ALT + SPACE") ~= nil and probe_bind("", "SUPER + SPACE") == nil)
check("leader ALT: Go entry key", probe_bind("", "ALT + G") ~= nil and probe_bind("", "SUPER + G") == nil)
Stubs.load(Stubs.VARIANTS[1], { "keymaps.global", "keymaps.submaps.leader", "keymaps.submaps.go" })
check("default leader: Leader entry key", probe_bind("", "SUPER + SPACE") ~= nil and probe_bind("", "SPACE") == nil)
check("default leader: Go entry key", probe_bind("", "SUPER + G") ~= nil and probe_bind("", "G") == nil)

-- the leader plus SPACE enters the Leader submap, a one-shot menu
check("leader SPACE enters Leader", pressed("", "SUPER + SPACE") == "submap(Leader)")
check("Leader is one-shot", pressed("Leader", "catchall") == "submap(reset)")

-- ESCAPE: out of every submap, back one level, into a named submap, or no ESCAPE
local Submap = probes({
	{ name = "Outer", binds = ROWS },
	{ name = "Reset", binds = ROWS },
	{ name = "Previous", escape = "previous", binds = ROWS },
	{ name = "Named", escape = "Outer", binds = ROWS },
	{ name = "Never", escape = false, binds = ROWS },
})
check("ESCAPE: out of every submap by default", pressed("Reset", "ESCAPE") == "submap(reset)")
check("ESCAPE: labelled with the submap", probe_bind("Reset", "ESCAPE").opts.desc == "Exit Reset")
check("ESCAPE: into a named submap", pressed("Named", "ESCAPE") == "submap(Outer)")
Submap.enter("Outer")
Submap.enter("Previous")
check("ESCAPE: back one level", pressed("Previous", "ESCAPE") == "submap(Outer)")
Submap.reset()
Submap.previous = nil
check("ESCAPE: previous with nowhere to go leaves", pressed("Previous", "ESCAPE") == "submap(reset)")
check("ESCAPE: a submap can have none", probe_bind("Never", "ESCAPE") == nil)

-- BACKSPACE: the submap you came from, else out
Submap.enter("Outer")
Submap.enter("Reset")
check("BACKSPACE: back to the submap before", pressed("Reset", "BackSpace") == "submap(Outer)")
Submap.reset()
Submap.previous = nil
check("BACKSPACE: out when there is none", pressed("Reset", "BackSpace") == "submap(reset)")

-- one-shot: an unbound key just leaves; stay: an unbound key does nothing
probes({
	{ name = "Once", catchall = "reset", binds = ROWS },
	{ name = "Stay", catchall = "stay", binds = ROWS },
})
check("one-shot: unbound key leaves", pressed("Once", "catchall") == "submap(reset)")
check("stay: unbound key is swallowed", pressed("Stay", "catchall") == "no_op")
check("stay: nothing leaves the submap", not pressed("Stay", "catchall"):find("submap", 1, true))
-- one-shot: holding a modifier for a chord row does not leave
for _, key in ipairs({ "Shift_L", "Shift_R", "Control_L", "Control_R", "Alt_L", "Alt_R", "Super_L", "Super_R" }) do
	local modifier = probe_bind("Once", key)
	check(
		"one-shot: " .. key .. " alone stays",
		modifier and pressed("Once", key) == "no_op" and modifier.opts.ignore_mods and modifier.opts.transparent
	)
end
local slash = probe_bind("Once", "SLASH")
check(
	"one-shot: SLASH key-up no-op (Hyprland 0.56 release catchall)",
	slash and pressed("Once", "SLASH") == "no_op" and slash.opts.ignore_mods and slash.opts.transparent
)

-- SHIFT + SLASH toggles which-key, unlabelled; a submap's own row on that key wins
probes({
	{ name = "Plain", binds = ROWS },
	{ name = "Own", binds = { { "shift+slash", "terminal.open", "Own help" } } },
})
local toggle = probe_bind("Plain", "SHIFT + SLASH")
check("which-key toggle is bound", toggle ~= nil)
check("which-key toggle has no description", toggle and toggle.opts.desc == nil)
check("which-key toggle toggles", pressed("Plain", "SHIFT + SLASH") == "hyprvim.whichkey.toggle()")
check("a row on that key keeps its row", probe_bind("Own", "SHIFT + SLASH") == nil and probe_bind("Own", "shift+slash"))

-- a submap of your own: name, entry key, label, escape, one-shot setting, rows
probes({
	{
		name = "Notes",
		desc = "+Notes",
		enter = "SUPER + SHIFT + N",
		escape = "reset",
		catchall = "reset",
		binds = { { "T", "terminal.open", "Today" } },
	},
})
check("own submap: entry key", pressed("", "SUPER + SHIFT + N") == "submap(Notes)")
check("own submap: its row", probe_bind("Notes", "T") ~= nil and probe_bind("Notes", "T").opts.desc == "Today")
check("own submap: ESCAPE", pressed("Notes", "ESCAPE") == "submap(reset)")
check("own submap: one-shot", pressed("Notes", "catchall") == "submap(reset)")

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("act submap rows: all passed")
