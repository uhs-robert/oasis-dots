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

-- Every key performs the manifest's performer: argv joined for a command, `qs-ipc call` for an IPC function. None
-- of these words needs quoting, and ~/ stays for the shell to expand.
local function performed(key)
	executed = {}
	find(key).action()
	return executed[1]
end
local bindings_file = assert(io.open(manifest_dir .. "/bindings/quickshell.json"))
local performers = Json.decode(bindings_file:read("a")).bindings
bindings_file:close()

local function expected_command(performer)
	if performer.kind == "ipc" then
		local words = { "~/.config/hypr/scripts/qs-ipc", "call", performer.target, performer["function"] }
		for _, arg in ipairs(performer.args) do
			words[#words + 1] = arg
		end
		return table.concat(words, " ")
	end
	return table.concat(performer.argv, " ")
end

for _, entry in ipairs(manifest) do
	local performer = performers[entry.id]
	check(entry.id .. ": has a performer", performer ~= nil)
	check(
		entry.id .. ": performs " .. (performer and expected_command(performer) or "?"),
		performer ~= nil and performed(bound_key(entry.key)) == expected_command(performer)
	)
	for _, extra in ipairs(entry.extra_keys) do
		check(
			entry.id .. ": extra key performs the same",
			performed(bound_key(extra)) == performed(bound_key(entry.key))
		)
	end
end

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
