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
local broken, _, broken_ok, broken_err, broken_warnings = bind_set({ "keymaps.global", "keymaps.submaps" })
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

-- Failing partway is harder: global power.lua raises after all its binds, and the Go submap's body raises after one
-- bind inside it. Hyprland's current submap must be back to global once the Go file fails, so the later submaps'
-- entry keys stay global, and Go gets no entry key into a submap with no Escape.
local hypr_dir = here .. "/../.config/hypr"
package.preload["keymaps.global.power"] = function()
	assert(loadfile(hypr_dir .. "/keymaps/global/power.lua"))()
	error("power broke after binding")
end
package.preload["keymaps.submaps.go"] = function()
	local Submap = require("lib.key.submap")
	local Bind = require("lib.key.bind")
	local define = Submap.define
	Submap.define = function(spec)
		spec.binds = function()
			Bind.key("F12", function() end, "Half")
			error("go broke midway")
		end
		return define(spec)
	end
	local ok_go, err_go = pcall(assert(loadfile(hypr_dir .. "/keymaps/submaps/go/init.lua")))
	Submap.define = define
	if not ok_go then
		error(err_go, 0)
	end
end
local partial, _, partial_ok, partial_err, partial_warnings = bind_set({ "keymaps.global", "keymaps.submaps" })
package.preload["keymaps.global.power"] = nil
package.preload["keymaps.submaps.go"] = nil
local Bind_after = require("lib.key.bind")
check("keymaps load around files that fail partway: " .. tostring(partial_err), partial_ok)
check("Bind.submap raises only after hl.define_submap returns", Stubs.submap_body_errors == 0)
for signature, bind in pairs(clean) do
	if bind.submap == "Go" or bind.opts.desc == "+Go" then
		check("the half-built Go submap loses " .. signature, not partial[signature])
	else
		check("a file failing partway leaves " .. signature, partial[signature])
	end
end
for signature, bind in pairs(partial) do
	check("nothing leaks out of the half-built submap: " .. signature, clean[signature] or bind.submap == "Go")
end
check("the failed Go body's F12 bind is not left bound", not Bind_after.is_bound("F12", "Go"))
local f12_removed = false
for _, bind in ipairs(Stubs.binds) do
	if bind.submap == "Go" and bind.key == "F12" and bind.removed then
		f12_removed = true
	end
end
check("the failed Go body's F12 bind was removed from Hyprland", f12_removed)

-- A failed body that re-binds a key bound by an earlier call loses only its own handle.
Bind_after.submap("Rollback", function()
	Bind_after.key("F11", function() end, "Earlier")
end)
local earlier_handle = Stubs.binds[#Stubs.binds]
local rollback_ok, rollback_err = pcall(Bind_after.submap, "Rollback", function()
	Bind_after.key("F11", function() end, "Again")
	error("rollback body broke", 0)
end)
local again_handle = Stubs.binds[#Stubs.binds]
check(
	"a failed body's error is rethrown",
	not rollback_ok and tostring(rollback_err):find("rollback body broke", 1, true) ~= nil
)
check("the failed body's re-bind was removed", again_handle.removed == true)
check("the earlier bind of that key was not removed", not earlier_handle.removed)
check("the earlier bind of that key is still bound", Bind_after.is_bound("F11", "Rollback", earlier_handle))
check("the failed body's re-bind is not bound", not Bind_after.is_bound("F11", "Rollback", again_handle))

-- A removal that raises during rollback must not replace the body's error.
local doomed_handle
local broken_ok, broken_err2 = pcall(Bind_after.submap, "Rollback", function()
	local doomed = Bind_after.key("F10", function() end, "Doomed")
	doomed_handle = doomed[1]
	doomed[1].remove = function()
		error("remove broke", 0)
	end
	error("body broke first", 0)
end)
check(
	"a raising rollback keeps the body's error",
	not broken_ok and tostring(broken_err2):find("body broke first", 1, true) ~= nil
)
check("a raising removal leaves the handle tracked", Bind_after.is_bound("F10", "Rollback", doomed_handle))

-- A body that unbinds a pre-bound key and binds it again keeps the handle count; only the new handle goes.
Bind_after.submap("Swap", function()
	Bind_after.key("F9", function() end, "Original")
end)
local original_handle = Stubs.binds[#Stubs.binds]
pcall(Bind_after.submap, "Swap", function()
	Bind_after.unbind("F9", "Swap")
	Bind_after.key("F9", function() end, "Replacement")
	error("swap body broke", 0)
end)
local replacement_handle = Stubs.binds[#Stubs.binds]
check("unbind then re-bind then raise removes the replacement", replacement_handle.removed == true)
check("the replacement is not left bound", not Bind_after.is_bound("F9", "Swap", replacement_handle))

local entry_keys = 0
for _, bind in pairs(clean) do
	local desc = bind.opts.desc
	if bind.submap == "" and type(desc) == "string" and desc:sub(1, 1) == "+" and desc ~= "+Go" then
		entry_keys = entry_keys + 1
		check("Bind tracks the " .. desc .. " entry key as global", Bind_after.is_bound(bind.key, nil))
	end
end
check("later submaps have entry keys to check", entry_keys > 0)
check("Bind has no Go entry key", not Bind_after.is_bound("SUPER + G", nil))
local partial_warned = table.concat(partial_warnings, "\n")
local function count_partial_warnings(text)
	local count = 0
	for _, warning in ipairs(partial_warnings) do
		if warning:find(text, 1, true) then
			count = count + 1
		end
	end
	return count
end
check(
	"warns once naming keymaps/global/power.lua: " .. partial_warned,
	count_partial_warnings("keymaps/global/power.lua failed to load") == 1
)
check(
	"warns once naming the half-built Go submap: " .. partial_warned,
	count_partial_warnings("keymaps/submaps/go/init.lua failed to load") == 1
)
check("warns about nothing else after a partial failure: " .. partial_warned, #partial_warnings == 2)

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("act ipc: all passed")
