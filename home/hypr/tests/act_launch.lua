-- Loads keymaps/global/{shortcuts,tools}.lua against a stubbed `hl` under two Config shapes (with and without a
-- leader) and compares every registered bind with fixtures/act_launch_binds.tsv: submap, key, which-key label, flags
-- and what the key does. The fixture was dumped from the keymaps as they were before the launch keys were actions and
-- is unchanged by that move. It also checks the new action ids exist, carry the labels and run by name.
--
--   SHELL=/bin/zsh lua home/hypr/tests/act_launch.lua          compare with the fixture
--   SHELL=/bin/zsh lua home/hypr/tests/act_launch.lua --dump   print the current binds in the fixture's format
local here = arg[0]:match("^(.*)/[^/]*$") or "."
local Stubs = dofile(here .. "/act_stubs.lua")

-- Bar is loaded because pressing a key that enters a submap fails while it is unknown; only the global binds are compared.
local MODULES = { "keymaps.global.shortcuts", "keymaps.global.tools", "keymaps.submaps.bar" }
local function in_global_map(submap)
	return submap == ""
end

if arg[1] == "--dump" then
	print(table.concat(Stubs.dump_lines(MODULES, in_global_map), "\n"))
	os.exit(0)
end

local failures = Stubs.compare(MODULES, here .. "/fixtures/act_launch_binds.tsv", in_global_map)
local function check(name, ok)
	if not ok then
		failures = failures + 1
		print("FAIL " .. name)
	end
end

Stubs.load(Stubs.VARIANTS[1], MODULES)
local Act = require("lib.act")
check("no warnings: " .. table.concat(Act.warnings, "; "), #Act.warnings == 0)
local handles = {}
for _, handle in ipairs(Act.list()) do
	handles[handle.id] = handle
end

local EXPECTED = {
	{ "terminal.open", "Terminal" },
	{ "terminal.bottom", "Bottom Terminal" },
	{ "menu.ssh", "SSH Select" },
	{ "menu.run_script", "Run Script" },
	{ "files.open", "File Manager" },
	{ "terminal.tui_files", "TUI File Manager" },
	{ "menu.drun", "Open Application" },
	{ "menu.cli", "Run CLI Tool" },
	{ "menu.agents", "Agent Sessions" },
	{ "hyprvim.edit_selection", "Edit Selection in Vim" },
	{ "terminal.yazi", "Yazi" },
	{ "terminal.task_manager", "Task Manager" },
	{ "submap.enter", "Enter Submap" },
}
for _, expected in ipairs(EXPECTED) do
	local handle = handles[expected[1]]
	check("defined: " .. expected[1], handle ~= nil)
	check("label of " .. expected[1], handle ~= nil and handle.label == expected[2])
end

local function ran(id, ...)
	Stubs.performed = {}
	local ok, err = pcall(Act.run, id, ...)
	return ok and table.concat(Stubs.performed, ";") or ("ERROR " .. tostring(err))
end
check("run terminal.open", ran("terminal.open") == "exec_cmd(kitty --single-instance)")
check("run files.open", ran("files.open") == "exec_cmd(thunar)")
check("run terminal.tui_files", ran("terminal.tui_files") == "exec_cmd(kitty --single-instance -e yazi)")
check("run hyprvim.edit_selection", ran("hyprvim.edit_selection") == "hyprvim.editor.open({insert_mode=true})")
-- Config is read when the action runs, not when the file loads.
package.loaded["config"].app.tui_file_manager = "ranger"
package.loaded["config"].app.gui_file_manager = "nautilus"
check("run terminal.tui_files follows Config", ran("terminal.tui_files") == "exec_cmd(kitty --single-instance -e ranger)")
check("run files.open follows Config", ran("files.open") == "exec_cmd(nautilus)")
-- Only a loaded submap can be entered: an unknown name raises, which is what makes `hypr-act` exit 5.
check("submap.enter unknown name raises", ran("submap.enter", "Typo"):match("^ERROR.*unknown submap 'Typo'") ~= nil)
check("run submap.enter", ran("submap.enter", "Bar") == "submap(Bar)")
check("submap.enter needs a name", ran("submap.enter"):match("^ERROR") ~= nil)

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("act launch: all passed")
