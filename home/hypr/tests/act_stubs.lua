-- Shared by act_launch.lua and act_submap_rows.lua: a stubbed `hl`, the repo's default Config with two shapes, and a
-- dump of every registered bind (submap, key, which-key label, flags, what it does) that the tests compare with a
-- fixture dumped from the keymaps before their keys were actions.
local Stubs = {}

local here = arg[0]:match("^(.*)/[^/]*$") or "."
local hypr_dir = here .. "/../.config/hypr"
package.path = hypr_dir .. "/?.lua;" .. hypr_dir .. "/?/init.lua;" .. package.path

Stubs.binds = {}
Stubs.performed = {}
local current_submap = ""

local function serialize(value)
	if type(value) ~= "table" then
		return tostring(value)
	end
	local keys = {}
	for key in pairs(value) do
		keys[#keys + 1] = tostring(key)
	end
	table.sort(keys)
	local parts = {}
	for _, key in ipairs(keys) do
		parts[#parts + 1] = key .. "=" .. serialize(value[key] ~= nil and value[key] or value[tonumber(key)])
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

--- hl.dsp.<name>(...) and hl.dsp.<group>.<name>(...) build a dispatcher whose text hl.dispatch records.
local function dsp_stub()
	return setmetatable({}, {
		__index = function(self, name)
			local function maker(...)
				local args = { ... }
				local text = name
				if #args > 0 then
					text = text .. "(" .. serialize(args[1]) .. ")"
				end
				return { text = text }
			end
			local group = setmetatable({}, {
				__index = function(_, inner)
					return function(...)
						local made = maker(...)
						made.text = name .. "." .. inner .. made.text:sub(#name + 1)
						return made
					end
				end,
				__call = function(_, ...)
					return maker(...)
				end,
			})
			rawset(self, name, group)
			return group
		end,
	})
end

--- A module stand-in that records every call made through it, e.g. "hyprvim.editor.open({insert_mode=true})".
local function recorder(path)
	return setmetatable({}, {
		__index = function(_, name)
			return recorder(path .. "." .. name)
		end,
		__call = function(_, ...)
			local args = { ... }
			Stubs.performed[#Stubs.performed + 1] = path .. "(" .. (#args > 0 and serialize(args[1]) or "") .. ")"
		end,
	})
end

_G.hl = setmetatable({
	version = function()
		return "0.57.0"
	end,
	bind = function(key, action, opts)
		local copy = {}
		for name, value in pairs(opts or {}) do
			copy[name] = value
		end
		local entry = { submap = current_submap, key = key, action = action, opts = copy }
		function entry:remove() end
		Stubs.binds[#Stubs.binds + 1] = entry
		return entry
	end,
	define_submap = function(name, a, b)
		local body = b or a
		local previous = current_submap
		current_submap = name
		body()
		current_submap = previous
	end,
	timer = function() end,
	notification = { create = function() end },
	get_windows = function()
		return {}
	end,
	get_monitors = function()
		return {}
	end,
	get_active_window = function()
		return "ACTIVE"
	end,
	get_current_submap = function()
		return ""
	end,
	dsp = dsp_stub(),
	dispatch = function(dispatcher)
		Stubs.performed[#Stubs.performed + 1] = dispatcher.text
	end,
}, {
	__index = function()
		return function() end
	end,
})

Stubs.VARIANTS = {
	{ name = "default", leader = "SUPER", monitors = {} },
	{
		name = "no-leader",
		leader = "",
		monitors = { { name = "DP-1" }, { description = "Some Monitor" }, { name = "HDMI-A-1" } },
	},
}

--- Load `modules` fresh under a variant, with the modules that reach the session or optional repos stubbed.
function Stubs.load(variant, modules)
	for name in pairs(package.loaded) do
		if name:match("^lib%.") or name:match("^keymaps%.") then
			package.loaded[name] = nil
		end
	end
	Stubs.binds, Stubs.performed, current_submap = {}, {}, ""
	package.loaded["lua.plugins.hyprvim"] = recorder("hyprvim")
	package.loaded["config.rules"] = recorder("rules")
	-- Real functions, not recorders: a submap runs a function row itself and hands anything else to hl.dispatch.
	package.loaded["config.autostart"] = function()
		Stubs.performed[#Stubs.performed + 1] = "autostart.run()"
	end
	package.loaded["extensions.auto_launcher.launcher"] = {
		show_picker = function()
			Stubs.performed[#Stubs.performed + 1] = "launcher.show_picker()"
		end,
	}

	-- The repo defaults with the derived fields set by hand: Config.merge would probe the machine.
	local Config = require("config")
	local Utils = require("lib.utils")
	for name, value in pairs(Utils.deep_extend({}, Config.defaults)) do
		Config[name] = value
	end
	Config.app.term = "kitty"
	Config.app.term_cmd = "kitty --single-instance"
	Config.app.dmenu_cmd = "rofi -name rofiDmenu -i -dmenu"
	Config.is_laptop = false
	Config.nvidia = { enable = false, backend = "nvidia-drm", hybrid = false }
	Config.ws_per_monitor = Config.persistent_workspaces
	Config.leader = variant.leader
	Config.monitors = variant.monitors
	for _, module in ipairs(modules) do
		require(module)
	end
end

local function flags_of(opts)
	local flags = {}
	for key, value in pairs(opts) do
		if key ~= "desc" then
			flags[#flags + 1] = key .. "=" .. tostring(value)
		end
	end
	table.sort(flags)
	return #flags > 0 and table.concat(flags, ",") or "-"
end

--- One text line per bind, sorted: variant, submap, key, label, flags, what the key does. With `keep`, only the binds
--- it returns true for (given the bind's submap name, "" for the global map) are listed.
function Stubs.dump_lines(modules, keep)
	local lines = {}
	for _, variant in ipairs(Stubs.VARIANTS) do
		Stubs.load(variant, modules)
		for _, entry in ipairs(Stubs.binds) do
			if keep and not keep(entry.submap) then
				goto skip
			end
			Stubs.performed = {}
			local ok, err
			if type(entry.action) == "function" then
				ok, err = pcall(entry.action)
			else
				ok, err = pcall(hl.dispatch, entry.action)
			end
			local what = ok and table.concat(Stubs.performed, ";") or ("ERROR " .. tostring(err))
			lines[#lines + 1] = table.concat({
				variant.name,
				entry.submap ~= "" and entry.submap or "-",
				entry.key,
				entry.opts.desc or "-",
				flags_of(entry.opts),
				what ~= "" and what or "-",
			}, "\t")
			::skip::
		end
	end
	table.sort(lines)
	return lines
end

--- Compare the dump with a fixture file; returns the number of failures (each printed).
function Stubs.compare(modules, fixture_path, keep)
	local failures = 0
	local expected_set, actual_set, expected_count = {}, {}, 0
	for line in io.lines(fixture_path) do
		if line ~= "" and line:sub(1, 1) ~= "#" then
			expected_set[line] = true
			expected_count = expected_count + 1
		end
	end
	local actual = Stubs.dump_lines(modules, keep)
	for _, line in ipairs(actual) do
		actual_set[line] = true
		if not expected_set[line] then
			failures = failures + 1
			print("FAIL unexpected bind: " .. line)
		end
	end
	for line in pairs(expected_set) do
		if not actual_set[line] then
			failures = failures + 1
			print("FAIL missing bind: " .. line)
		end
	end
	if #actual ~= expected_count then
		failures = failures + 1
		print("FAIL bind count " .. #actual .. " vs " .. expected_count)
	end
	return failures
end

return Stubs
