-- Loads the keyless IPC action definitions (lib/actions/defs/{notifications,style,lock,power,screenshot,zoom,overview,
-- settings,launcher}.lua) under a stubbed `hl`, runs every id with sample arguments and compares the command line it
-- would hand to Hyprland with the table below: the `qs-ipc call <target> <function> <args>` words, quoted for the shell.
-- It also checks that each of these actions has no key and that nothing else is defined in those files.
--
--   lua home/hypr/tests/act_ipc.lua           compare with the table
--   lua home/hypr/tests/act_ipc.lua --targets print "id<TAB>target<TAB>function" per action, for the declared-function check
local here = arg[0]:match("^(.*)/[^/]*$") or "."
-- Sets package.path and the stubbed `hl` shared with the other action tests.
dofile(here .. "/act_stubs.lua")

local FILES =
	{ "notifications", "style", "lock", "power", "screenshot", "zoom", "overview", "settings", "launcher" }

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

if arg[1] == "--targets" then
	for _, handle in ipairs(Act.list()) do
		if handle.run.kind == "ipc" then
			print(handle.id .. "\t" .. handle.run.target .. "\t" .. handle.run["function"])
		end
	end
	os.exit(0)
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
	check(
		id .. " sent " .. tostring(sent) .. ", wanted " .. expected,
		sent == Scripts.qs_ipc .. " call " .. expected
	)
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

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("act ipc: all passed")
