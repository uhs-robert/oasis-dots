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
	"window.focus_match",
	"terminal.tool",
	"terminal.editor",
	"workspace.focus_last",
	"system.update",
	"system.edit_keymaps",
	"system.theme_switch",
}) do
	check("defined: " .. id, ids[id] ~= nil)
end
-- The app names an action takes are exactly the names Apps.map has, so a new app cannot be left out by accident.
local Apps = require("lib.actions.apps")
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

-- The row form, on its own submap in a fresh load.
local function row_binds(rows, catchall)
	Stubs.load(Stubs.VARIANTS[1], { "keymaps.global", "lib.actions.defs.apps" })
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
	{ "I", { "apps.open", { "gimp" } } },
})
check("row: id takes the action's label", found.A and found.A.opts.desc == "Terminal")
check("row: desc overrides the label", found.B and found.B.opts.desc == "Own Label")
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
check("row: args reach the action", table.concat(Stubs.performed, ";") == "exec_cmd(gimp)")

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

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("act submap rows: all passed")
