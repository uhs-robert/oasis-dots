-- Runs lib/actions/defs/tools.lua against a stubbed `hl`: the 14 tool actions register the keys, extra keys and
-- labels written out below, nothing warns, each key runs the command written out below, and their binds can be
-- removed with Bind.unbind.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
local hypr_dir = here .. "/../.config/hypr"
package.path = hypr_dir .. "/?.lua;" .. hypr_dir .. "/?/init.lua;" .. package.path

package.loaded["config"] = { leader = "SUPER" }

local binds, removed, timers, executed = {}, {}, {}, {}
_G.hl = {
	version = function()
		return "0.57.0"
	end,
	bind = function(key, action, opts)
		local entry = { key = key, action = action, opts = opts }
		function entry:remove()
			removed[#removed + 1] = key
		end
		binds[#binds + 1] = entry
		return entry
	end,
	timer = function(fn)
		timers[#timers + 1] = fn
	end,
	notification = { create = function() end },
	dsp = {
		exec_cmd = function(cmd)
			return { exec = cmd }
		end,
	},
	dispatch = function(dispatcher)
		executed[#executed + 1] = dispatcher.exec
	end,
}

local failures = 0
local function check(name, ok)
	if not ok then
		failures = failures + 1
		print("FAIL " .. name)
	end
end

local Bind = require("lib.key.bind")
local Act = require("lib.act")
check("Bind.action is gone", Bind.action == nil)

require("lib.actions.defs.tools")
check("no warnings", #Act.warnings == 0)

local function find(key)
	for _, entry in ipairs(binds) do
		if entry.key == key then
			return entry
		end
	end
end

-- The 14 actions as the keymaps shipped them before Act: id, label, keys (the leader is SUPER here) and the command
-- each key runs. None of the words needs quoting, and ~/ stays for the shell to expand.
local qs_ipc = "~/.config/hypr/scripts/qs-ipc call "
local screenshot = "~/.config/hypr/scripts/screenshot.sh"
local voxcmd = "~/.local/bin/voxcmd "
local expected = {
	{ "screenshot.take", "Screenshot", { "Print", "SUPER + I" }, screenshot, universal = { Print = true } },
	{ "screenshot.pixel", "Color Picker", { "SUPER + P" }, screenshot .. " --pixel" },
	{ "zoom.toggle", "Zoom", { "SUPER + Z" }, qs_ipc .. "zoom toggle" },
	{ "voice.dictate", "Speech to Text", { "SUPER + PERIOD" }, "~/.config/hypr/scripts/voxtype-with-media-pause.sh" },
	{ "voice.command", "Voice Command", { "SUPER + COMMA" }, voxcmd .. "listen" },
	{ "voice.stop", "Stop Voice", { "SUPER + SHIFT + COMMA" }, voxcmd .. "stop" },
	{ "voice.rapid", "Rapid Mode", { "SUPER + CTRL + COMMA" }, voxcmd .. "rapid" },
	{ "voice.wake", "Wake Word", { "SUPER + CTRL + PERIOD" }, voxcmd .. "wake toggle" },
	{ "picker.passwords", "Passwords", { "SUPER + CTRL + P" }, "rofi-rbw" },
	{ "overview.search", "Search windows", { "SUPER + T" }, qs_ipc .. "overview search" },
	{ "overview.move", "Move window in overview", { "SUPER + SHIFT + T" }, qs_ipc .. "overview move_follow" },
	{
		"overview.move_silent",
		"Silent move window in overview",
		{ "SUPER + CTRL + SHIFT + T" },
		qs_ipc .. "overview move_silent",
	},
	{ "overview.open", "Workspace overview", { "ALT + TAB", "SUPER + TAB" }, qs_ipc .. "overview open" },
	{ "tmux.overview", "Tmux overview", { "ALT + GRAVE" }, qs_ipc .. "tmux_overview open" },
}
check("14 actions", #expected == 14)

-- Every key performs its action's command: argv joined for a command, `qs-ipc call` for an IPC function.
local function performed(key)
	executed = {}
	find(key).action()
	return executed[1]
end

local expected_binds = 0
for _, entry in ipairs(expected) do
	local id, label, keys, command = entry[1], entry[2], entry[3], entry[4]
	for _, key in ipairs(keys) do
		expected_binds = expected_binds + 1
		local bind = find(key)
		check(id .. ": bound " .. key, bind ~= nil)
		check(id .. ": label " .. key, bind and bind.opts.desc == label)
		check(
			id .. ": universal " .. key,
			bind and (bind.opts.submap_universal == true) == ((entry.universal or {})[key] == true)
		)
		check(id .. ": " .. key .. " performs " .. command, bind and performed(key) == command)
	end
end
check("no other binds", #binds == expected_binds)

-- The same ids run by name, as the bar and voice will.
executed = {}
Act.run("tmux.overview")
check("run by id", executed[1] == "~/.config/hypr/scripts/qs-ipc call tmux_overview open")

-- Bind.unbind removes what Act.define registered, extras included.
check("unbind: main key", Bind.unbind("Print") == 1)
check("unbind: leader extra", Bind.leader_unbind("I") == 1)
check("unbind: handles removed", #removed == 2)
check("unbind: nothing left", Bind.unbind("Print") == 0)

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("bind action: all passed")
