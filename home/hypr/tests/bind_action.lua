-- Runs lib/actions/defs/tools.lua against a stubbed `hl`: the 14 tool actions register the keys, extra keys and
-- labels the hand-written manifest has, nothing warns, they run through Cmd/Ipc argv, and their binds can be
-- removed with Bind.unbind. The hand-written manifest is read only for the expected values, until it is deleted.
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

-- Every manifest entry: same key, extra keys, label and universal flag, in the manifest's order.
local manifest_dir = here .. "/../../oasis-djinn/.config/oasis-djinn"
local file = assert(io.open(manifest_dir .. "/actions.json"))
local text = file:read("a")
file:close()
local Json = require("lib.json")
local manifest = Json.decode(text).actions
check("manifest has 14 actions", #manifest == 14)

local function bound_key(spec)
	return spec.leader and ("SUPER + " .. spec.key) or spec.key
end

local expected_binds = 0
for _, entry in ipairs(manifest) do
	local keys = { entry.key }
	for _, extra in ipairs(entry.extra_keys) do
		keys[#keys + 1] = extra
	end
	for _, spec in ipairs(keys) do
		expected_binds = expected_binds + 1
		local bind = find(bound_key(spec))
		check(entry.id .. ": bound " .. bound_key(spec), bind ~= nil)
		check(entry.id .. ": label " .. bound_key(spec), bind and bind.opts.desc == entry.label)
		check(
			entry.id .. ": universal " .. bound_key(spec),
			bind and (bind.opts.submap_universal == true) == spec.universal
		)
	end
end
check("no other binds", #binds == expected_binds)

-- The keys perform through argv: no shell word is split, and ~/ stays for the shell to expand.
local function performed(key)
	executed = {}
	find(key).action()
	return executed[1]
end
check("zoom: ipc call", performed("SUPER + Z") == "~/.config/hypr/scripts/qs-ipc call zoom toggle")
check("pixel: argv", performed("SUPER + P") == "~/.config/hypr/scripts/screenshot.sh --pixel")
check("wake: argv", performed("SUPER + CTRL + PERIOD") == "~/.local/bin/voxcmd wake toggle")
check("passwords: bare program", performed("SUPER + CTRL + P") == "rofi-rbw")
check(
	"overview move: ipc function",
	performed("SUPER + SHIFT + T") == "~/.config/hypr/scripts/qs-ipc call overview move_follow"
)
check("extra key runs the same action", performed("SUPER + I") == performed("Print"))

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
