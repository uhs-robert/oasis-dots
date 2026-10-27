-- Runs lib/actions/defs/tools.lua against a stubbed `hl`: the 14 tool actions register the keys, extra keys and
-- labels written out below, nothing warns, each key runs the command written out below, and their binds can be
-- removed with Bind.unbind. The rest covers the key helpers and Bind.unbind on keys of their own.
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
	define_submap = function(_, a, b)
		(b or a)()
	end,
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
	{ "voice.rapid", "Rapid Mode", { "SUPER + CTRL + COMMA" }, voxcmd .. "session rapid" },
	{ "voice.wake", "Wake Word", { "SUPER + CTRL + PERIOD" }, voxcmd .. "wake toggle" },
	{ "picker.passwords", "Passwords", { "SUPER + CTRL + P" }, "rofi-rbw" },
	{ "overview.search", "Search windows", { "SUPER + T" }, qs_ipc .. "overview search" },
	{ "overview.move", "Move window in overview", { "SUPER + SHIFT + T" }, qs_ipc .. "overview move_follow" },
	{ "overview.move_silent", "Silent move window in overview", {}, qs_ipc .. "overview move_silent" },
	{ "overview.open", "Workspace overview", { "ALT + TAB", "SUPER + TAB" }, qs_ipc .. "overview open" },
	{ "tmux.overview", "Tmux overview", { "ALT + GRAVE" }, qs_ipc .. "tmux_overview open" },
}
check("14 actions", #expected == 14)

-- req: KEYS-02, KEYS-03 (a bind with extra keys; the keys here carry the leader SUPER)
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
executed = {}
Act.run("overview.move_silent")
check("run keyless by id", executed[1] == "~/.config/hypr/scripts/qs-ipc call overview move_silent")

-- req: KEYS-08 (the screenshot key works in submaps)
check("Print works in submaps", find("Print").opts.submap_universal == true)

-- Bind.unbind removes what Act.define registered, extras included.
-- req: KEYS-27, KEYS-30 (the removal count, 0 when nothing matches, the leader form)
check("unbind: main key", Bind.unbind("Print") == 1)
check("unbind: leader extra", Bind.leader_unbind("I") == 1)
check("unbind: handles removed", #removed == 2)
check("unbind: nothing left", Bind.unbind("Print") == 0)

-- The key helpers and unbinding, on keys of their own. `bound_keys` lists what hl.bind received for a key.
local function bound_keys(key)
	local found = {}
	for _, entry in ipairs(binds) do
		if entry.key == key then
			found[#found + 1] = entry
		end
	end
	return found
end
local function was_removed(key)
	local count = 0
	for _, name in ipairs(removed) do
		if name == key then
			count = count + 1
		end
	end
	return count
end
local function noop() end

-- req: KEYS-01, KEYS-02 (key text reaches Hyprland as written; several keys share one action)
Bind.key("CTRL + SHIFT + ESCAPE", noop, "Chord")
check("key text is passed as written", #bound_keys("CTRL + SHIFT + ESCAPE") == 1)
Bind.key({ "F1", "F2" }, noop, "Pair")
check("several keys: one bind each", #bound_keys("F1") == 1 and #bound_keys("F2") == 1)
check("several keys: the same action", bound_keys("F1")[1].action == bound_keys("F2")[1].action)

-- req: KEYS-03 (leader shortcuts carry the leader)
Bind.leader_cmd("F9", "calc", "Calculator")
check("leader: SUPER + key", #bound_keys("SUPER + F9") == 1)
check("leader: the command runs", bound_keys("SUPER + F9")[1].action.exec == "calc")

-- req: KEYS-09 (a bind of your own can be marked to work in submaps)
Bind.leader_cmd("F10", "calc", { submap_universal = true, desc = "Calculator" })
check("custom bind: universal flag reaches the bind", bound_keys("SUPER + F10")[1].opts.submap_universal == true)
check("custom bind: description reaches the bind", bound_keys("SUPER + F10")[1].opts.desc == "Calculator")

-- req: KEYS-28 (case and spaces do not matter when unbinding)
Bind.key("SUPER + F8", noop, "Spelling")
check("unbind: other case and spacing", Bind.unbind("super+f8") == 1)
check("unbind: the bind was removed", was_removed("SUPER + F8") == 1)
check("unbind: no longer live", not Bind.is_bound("SUPER + F8"))

-- req: KEYS-29 (a named submap, or the global map, and nothing else)
Bind.key("H", noop, "Global H")
Bind.submap("Windows", function()
	Bind.key("H", noop, "Windows H")
	Bind.key("J", noop, "Windows J")
end)
Bind.submap("Resize", function()
	Bind.key("H", noop, "Resize H")
end)
check("unbind in one submap removes one bind", Bind.unbind("H", "Windows") == 1)
check("unbind in one submap: that submap loses it", not Bind.is_bound("H", "Windows"))
check("unbind in one submap: other submap keeps it", Bind.is_bound("H", "Resize"))
check("unbind in one submap: global keeps it", Bind.is_bound("H"))
check("unbind in one submap: its other keys stay", Bind.is_bound("J", "Windows"))
check("unbind without a submap: only the global map", Bind.unbind("H") == 1)
check("unbind without a submap: submaps keep theirs", Bind.is_bound("H", "Resize") and not Bind.is_bound("H"))

-- req: KEYS-30 (the leader form follows the leader; here the leader is replaced for a fresh Bind)
package.loaded["lib.key.bind"] = nil
package.loaded["config"] = { leader = "ALT" }
local Alt_bind = require("lib.key.bind")
Alt_bind.leader_fn("F11", noop, "Leader moved")
check("leader follows Config.leader", #bound_keys("ALT + F11") == 1 and Alt_bind.leader == "ALT")
check("leader unbind follows Config.leader", Alt_bind.leader_unbind("F11") == 1)
check("leader unbind: removed", was_removed("ALT + F11") == 1)
package.loaded["lib.key.bind"] = Bind
package.loaded["config"] = { leader = "SUPER" }

-- req: KEYS-31 (unbind, then bind again: one live bind, the new one)
local old = Bind.key("F7", noop, "Old")[1]
check("rebind: unbind removes the old", Bind.unbind("F7") == 1)
local new = Bind.key("F7", noop, "New")[1]
check("rebind: the new bind is live", Bind.is_bound("F7", nil, new))
check("rebind: the old bind is not", not Bind.is_bound("F7", nil, old))
check("rebind: only the old one was removed", was_removed("F7") == 1 and #bound_keys("F7") == 2)

-- req: KEYS-32 (a bind made any other way is left alone)
hl.bind("F6", noop, {})
check("raw bind: not counted", Bind.unbind("F6") == 0)
check("raw bind: not removed", was_removed("F6") == 0)

-- req: KEYS-33 (a named submap is created, then added to)
local before = #binds
Bind.submap("Notes", function()
	Bind.key("T", noop, "Today")
end)
Bind.submap("Notes", function()
	Bind.key("I", noop, "Inbox")
end)
check("submap: both calls added binds", #binds == before + 2)
check("submap: both keys are in it", Bind.is_bound("T", "Notes") and Bind.is_bound("I", "Notes"))
check("submap: neither is global", not Bind.is_bound("T") and not Bind.is_bound("I"))

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("bind action: all passed")
