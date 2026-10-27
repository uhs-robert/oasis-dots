-- Loads the keyless IPC action definitions (lib/actions/defs/{notifications,style,lock,power,screenshot,zoom,overview,
-- settings,launcher}.lua) under a stubbed `hl`, runs every id with sample arguments and compares the command line it
-- would hand to Hyprland with the table below: the `qs-ipc call <target> <function> <args>` words, quoted for the shell.
-- It also checks that each of these actions has no key, that nothing else is defined in those files, and that
-- requiring keymaps.global (what a live session loads) registers them all, even when one definition file is broken,
-- and that a broken keymap file costs only its own keys.
--
--   lua home/hypr/tests/act_ipc.lua
local here = arg[0]:match("^(.*)/[^/]*$") or "."
-- Sets package.path and the stubbed `hl` shared with the other action tests.
local Stubs = dofile(here .. "/act_stubs.lua")

local FILES = { "notifications", "style", "lock", "power", "screenshot", "zoom", "overview", "settings", "launcher" }

-- id, arguments (command-line words), what follows `qs-ipc call`.
local CASES = {
	{ "notifications.toggle_dnd", {}, "notifications toggle_dnd" },
	{ "notifications.clear_all", {}, "notifications clear_all" },
	{ "notifications.dismiss_latest", {}, "notifications dismiss_latest" },
	{ "notifications.dismiss_all", {}, "notifications dismiss_all" },
	{ "style.cycle", {}, "style cycle" },
	{ "style.set", { "crt" }, "style set crt" },
	{ "style.set", { "a b; rm" }, "style set 'a b; rm'" },
	{ "lock.open", {}, "lock lock" },
	{ "power.confirm", { "logout" }, "power confirm logout" },
	{ "power.confirm", { "poweroff" }, "power confirm poweroff" },
	{ "screenshot.menu", {}, "screenshot open" },
	{ "screenshot.select", { "true", "ocr" }, "screenshot select true ocr" },
	{ "screenshot.select", { "false", "toolbar" }, "screenshot select false toolbar" },
	{ "screenshot.stop_recording", {}, "screenshot stop_recording" },
	{ "zoom.step", { "-2" }, "zoom step -2" },
	{ "zoom.size", { "3" }, "zoom size 3" },
	{ "zoom.full", {}, "zoom full" },
	{ "overview.toggle", {}, "overview toggle" },
	{ "overview.close", {}, "overview close" },
	{ "tmux.toggle", {}, "tmux_overview toggle" },
	{ "tmux.close", {}, "tmux_overview close" },
	{ "tmux.search", {}, "tmux_overview search" },
	{ "settings.open", { "colors" }, "settings open colors" },
	{ "settings.open", {}, "settings open ''" },
	{ "settings.toggle", {}, "settings toggle" },
	{ "picker.open", { "emoji" }, "picker open emoji" },
	{ "picker.toggle", { "dirs" }, "picker toggle dirs" },
	{ "picker.close", {}, "picker close" },
}

-- Arguments that must be refused, not passed to the bar.
local REFUSED = {
	{ "power.confirm", { "hibernate" } },
	{ "power.confirm", {} },
	{ "style.set", {} },
	{ "screenshot.select", { "maybe", "ocr" } },
	{ "screenshot.select", { "true", "selfie" } },
	{ "zoom.step", { "1.5" } },
	{ "zoom.step", { "x" } },
	{ "picker.open", { "choices" } },
	{ "picker.open", {} },
}

local Act = require("lib.act")
local Scripts = require("lib.scripts")
for _, file in ipairs(FILES) do
	require("lib.actions.defs." .. file)
end

local failures = 0
local function check(name, ok)
	if not ok then
		failures = failures + 1
		print("FAIL " .. name)
	end
end

check("no warnings: " .. table.concat(Act.warnings, "; "), #Act.warnings == 0)

local sent
Act.exec = function(command)
	sent = command
end

local covered = {}
for _, case in ipairs(CASES) do
	local id, words, expected = case[1], case[2], case[3]
	covered[id] = true
	sent = nil
	local ok, err = pcall(Act.run_cli, id, words)
	check("run " .. id .. " " .. table.concat(words, " ") .. (ok and "" or ": " .. tostring(err)), ok)
	check(id .. " sent " .. tostring(sent) .. ", wanted " .. expected, sent == Scripts.qs_ipc .. " call " .. expected)
end
for _, case in ipairs(REFUSED) do
	sent = nil
	local ok = pcall(Act.run_cli, case[1], case[2])
	check("refuse " .. case[1] .. " " .. table.concat(case[2], " "), not ok and sent == nil)
end

-- Every action these files define is in the table (the files hold nothing else), and none has a key.
for _, handle in ipairs(Act.list()) do
	check("covered: " .. handle.id, covered[handle.id])
	check("keyless: " .. handle.id, handle.key == nil and #handle.extra_keys == 0)
end

-- The files above were required by name. A live session only loads what keymaps/global requires, so load that entry
-- from a clean slate and look for every id again.
for name in pairs(package.loaded) do
	if name:match("^lib%.act") or name:match("^keymaps") then
		package.loaded[name] = nil
	end
end
package.loaded["config"] = {
	leader = "SUPER",
	vim_mode = true,
	persistent_workspaces = false,
	monitors = {},
	app = { term_cmd = "kitty", gui_file_manager = "files", tui_file_manager = "yazi" },
}
package.loaded["lib.actions.menu"] = setmetatable({}, {
	__index = function()
		return function()
			return function() end
		end
	end,
})
local ok, err = xpcall(require, debug.traceback, "keymaps.global")
check("the real keymaps entry loads: " .. tostring(err), ok)
local loaded = {}
for _, handle in ipairs(require("lib.act").list()) do
	loaded[handle.id] = true
end
for id in pairs(covered) do
	check("keymaps.global registers " .. id, loaded[id])
end

-- One broken definition file costs only its own actions, across the whole keymaps load: keyless.lua and tools.lua
-- load each file on its own and warn naming the broken one, and the submaps that require it again (Leader for pickers,
-- System for power) must neither raise nor run it twice. pickers.lua defines its actions and then raises, power.lua
-- does not parse.
local pickers_path = here .. "/../.config/hypr/lib/actions/defs/pickers.lua"
package.preload["lib.actions.defs.pickers"] = function()
	assert(loadfile(pickers_path))()
	error("pickers broke after defining")
end
package.preload["lib.actions.defs.power"] = function()
	return assert(load("local = 1", "=lib/actions/defs/power.lua"))()
end
-- The real Config, not the cut-down one above: the submaps read more of it.
package.loaded["config"] = nil
ok, err = xpcall(Stubs.load, debug.traceback, Stubs.VARIANTS[1], { "keymaps.global", "keymaps.submaps" })
check("keymaps.global and keymaps.submaps load around broken definition files: " .. tostring(err), ok)
local act_after = require("lib.act")
local still_loaded = {}
for _, handle in ipairs(act_after.list()) do
	still_loaded[handle.id] = true
end
for id in pairs(covered) do
	if not id:match("^power%.") then
		check("a broken power.lua leaves " .. id, still_loaded[id])
	end
end
check("a broken pickers.lua leaves zoom.toggle from tools.lua", still_loaded["zoom.toggle"])
check("nothing from the broken power.lua", not still_loaded["power.confirm"])
local submaps_bound = {}
for _, bind in ipairs(Stubs.binds) do
	submaps_bound[bind.submap] = true
end
for _, submap in ipairs({ "Leader", "System", "Delete", "Windows" }) do
	check("the " .. submap .. " submap still binds keys", submaps_bound[submap])
end
local function count_warnings(text)
	local count = 0
	for _, warning in ipairs(act_after.warnings) do
		if warning:find(text, 1, true) then
			count = count + 1
		end
	end
	return count
end
local warned = table.concat(act_after.warnings, "\n")
check("warns once naming pickers.lua: " .. warned, count_warnings("lib/actions/defs/pickers.lua failed to load") == 1)
check("warns once naming power.lua: " .. warned, count_warnings("lib/actions/defs/power.lua failed to load") == 1)
check("no file runs twice: " .. warned, count_warnings("already defined") == 0)
package.preload["lib.actions.defs.pickers"] = nil
package.preload["lib.actions.defs.power"] = nil

-- The same holds one level up for keymap files: keymaps/global/init.lua and keymaps/submaps/init.lua load each file on
-- its own, so a broken one costs only its own keys. power.lua does not parse and the Go submap raises before it
-- defines anything; every other bind of a clean load must still be there, including the files after each.
local function bind_set(modules)
	package.loaded["config"] = nil
	local loaded_ok, load_err = xpcall(Stubs.load, debug.traceback, Stubs.VARIANTS[1], modules)
	local set, count = {}, 0
	for _, bind in ipairs(Stubs.binds) do
		set[bind.submap .. "\t" .. bind.key] = bind
		count = count + 1
	end
	return set, count, loaded_ok, load_err, require("lib.act").warnings
end
local clean = bind_set({ "keymaps.global", "keymaps.submaps" })
local power_only = bind_set({ "keymaps.global.power" })
package.preload["keymaps.global.power"] = function()
	return assert(load("local = 1", "=keymaps/global/power.lua"))()
end
package.preload["keymaps.submaps.go"] = function()
	error("go broke")
end
local broken, _, broken_ok, broken_err, broken_warnings =
	bind_set({ "keymaps.global", "keymaps.submaps" })
package.preload["keymaps.global.power"] = nil
package.preload["keymaps.submaps.go"] = nil
check("keymaps load around a broken keymap file: " .. tostring(broken_err), broken_ok)
local function owned_by_broken(signature, bind)
	return power_only[signature] ~= nil or bind.submap == "Go" or bind.opts.desc == "+Go"
end
local lost_power, lost_go = 0, 0
for signature, bind in pairs(clean) do
	if owned_by_broken(signature, bind) then
		check("the broken file's key is gone: " .. signature, not broken[signature])
		if bind.submap == "Go" then
			lost_go = lost_go + 1
		else
			lost_power = lost_power + 1
		end
	else
		check("a broken keymap file leaves " .. signature, broken[signature])
	end
end
check("keymaps/global/power.lua owns keys in a clean load", lost_power > 0)
check("the Go submap owns keys in a clean load", lost_go > 0)
for signature in pairs(broken) do
	check("no key appears only with broken files: " .. signature, clean[signature])
end
local keymap_warned = table.concat(broken_warnings, "\n")
local function count_keymap_warnings(text)
	local count = 0
	for _, warning in ipairs(broken_warnings) do
		if warning:find(text, 1, true) then
			count = count + 1
		end
	end
	return count
end
check(
	"warns once naming keymaps/global/power.lua: " .. keymap_warned,
	count_keymap_warnings("keymaps/global/power.lua failed to load") == 1
)
check(
	"warns once naming the Go submap file: " .. keymap_warned,
	count_keymap_warnings("keymaps/submaps/go/init.lua failed to load") == 1
)
check("warns about nothing else: " .. keymap_warned, #broken_warnings == 2)

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("act ipc: all passed")
