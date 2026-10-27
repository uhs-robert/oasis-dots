-- Loads the keyless IPC action definitions (lib/actions/defs/{notifications,style,lock,power,screenshot,zoom,overview,
-- settings,launcher}.lua) under a stubbed `hl`, runs every id with sample arguments and compares the command line it
-- would hand to Hyprland with the table below: the `qs-ipc call <target> <function> <args>` words, quoted for the shell.
-- It also checks that each of these actions has no key, that nothing else is defined in those files, and that
-- requiring keymaps.global (what a live session loads) registers them all, even when one definition file is broken.
--
--   lua home/hypr/tests/act_ipc.lua
local here = arg[0]:match("^(.*)/[^/]*$") or "."
-- Sets package.path and the stubbed `hl` shared with the other action tests.
dofile(here .. "/act_stubs.lua")

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

-- One broken definition file costs only its own actions: keyless.lua and tools.lua load each file on its own, warn
-- naming the broken one and carry on. style.lua raises while it runs, pickers.lua does not parse.
for name in pairs(package.loaded) do
	if name:match("^lib%.act") or name:match("^keymaps") then
		package.loaded[name] = nil
	end
end
package.preload["lib.actions.defs.style"] = function()
	error("style broke")
end
package.preload["lib.actions.defs.pickers"] = function()
	return assert(load("local = 1", "=lib/actions/defs/pickers.lua"))()
end
ok, err = xpcall(require, debug.traceback, "keymaps.global")
check("keymaps.global loads around broken definition files: " .. tostring(err), ok)
local act_after = require("lib.act")
local still_loaded = {}
for _, handle in ipairs(act_after.list()) do
	still_loaded[handle.id] = true
end
for id in pairs(covered) do
	if not id:match("^style%.") then
		check("a broken style.lua leaves " .. id, still_loaded[id])
	end
end
check("a broken pickers.lua leaves zoom.toggle from tools.lua", still_loaded["zoom.toggle"])
check("nothing from the broken style.lua", not still_loaded["style.cycle"] and not still_loaded["style.set"])
local warned = table.concat(act_after.warnings, "\n")
check("warns naming style.lua: " .. warned, warned:find("lib/actions/defs/style.lua failed to load", 1, true) ~= nil)
check(
	"warns naming pickers.lua: " .. warned,
	warned:find("lib/actions/defs/pickers.lua failed to load", 1, true) ~= nil
)
package.preload["lib.actions.defs.style"] = nil
package.preload["lib.actions.defs.pickers"] = nil

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("act ipc: all passed")
