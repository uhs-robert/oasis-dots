-- Loads keymaps/global/{general,workspace,media,mouse}.lua against a stubbed `hl` under four Config shapes (vim keys
-- or arrows, global or persistent workspaces, different monitor counts, with and without a leader) and compares every
-- registered bind with fixtures/act_global_binds.tsv: key, which-key label, flags and what the key dispatches. The
-- fixture was dumped from the keymaps as they were before these keys were actions, then only the three media labels the
-- change merges were edited (marked in the file). It also checks the action ids exist and run by name.
--
--   lua home/hypr/tests/act_global.lua          compare with the fixture
--   lua home/hypr/tests/act_global.lua --dump   print the current binds in the fixture's format
local here = arg[0]:match("^(.*)/[^/]*$") or "."
local hypr_dir = here .. "/../.config/hypr"
package.path = hypr_dir .. "/?.lua;" .. hypr_dir .. "/?/init.lua;" .. package.path

local CONFIGS = {
	{ name = "vim-global", leader = "SUPER", vim_mode = true, persistent_workspaces = false, monitors = {} },
	{
		name = "arrows-persistent",
		leader = "SUPER",
		vim_mode = false,
		persistent_workspaces = true,
		monitors = { 1, 2, 3 },
	},
	{
		name = "vim-persistent-4",
		leader = "SUPER",
		vim_mode = true,
		persistent_workspaces = 4,
		monitors = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 },
	},
	{ name = "vim-no-leader", leader = "", vim_mode = true, persistent_workspaces = false, monitors = { 1, 2 } },
}

local KEYMAPS = { "general", "workspace", "media", "mouse" }

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

local binds, performed

--- A dispatcher stub: calling hl.dsp.focus({...}) builds the text hl.dispatch later records.
local function dsp_stub()
	return setmetatable({}, {
		__index = function(self, name)
			local function maker(...)
				local args = { ... }
				local text = name
				if #args > 0 then
					text = text .. "(" .. serialize(args[1]) .. ")"
				end
				return setmetatable({ text = text }, {
					__index = function(_, field)
						return maker(field)
					end,
				})
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

_G.hl = {
	version = function()
		return "0.57.0"
	end,
	bind = function(key, action, opts)
		-- Copied like Hyprland does: the old media keymap shared one opts table and Bind.key writes `desc` into it.
		local copy = {}
		for name, value in pairs(opts) do
			copy[name] = value
		end
		local entry = { key = key, action = action, opts = copy }
		function entry:remove() end
		binds[#binds + 1] = entry
		return entry
	end,
	timer = function() end,
	notification = { create = function() end },
	get_active_window = function()
		return "ACTIVE"
	end,
	dsp = dsp_stub(),
	dispatch = function(dispatcher)
		performed[#performed + 1] = dispatcher.text
	end,
}

--- Load everything fresh under `config`, with the modules that reach the session stubbed to record what they get.
local function load_keymaps(config)
	for name in pairs(package.loaded) do
		if name:match("^lib%.") or name:match("^keymaps%.") then
			package.loaded[name] = nil
		end
	end
	binds, performed = {}, {}
	package.loaded["config"] = config
	package.loaded["lib.closed_windows"] = {
		close = function(windows, action)
			performed[#performed + 1] = "closed.close(" .. tostring(windows[1]) .. "," .. action .. ")"
		end,
		restore = function()
			performed[#performed + 1] = "closed.restore"
		end,
	}
	package.loaded["lib.workspaces"] = {
		get_monitor_for_slot = function(slot)
			return "MON" .. slot
		end,
	}
	package.loaded["lib.actions.menu"] = {
		keybinds = function()
			return function()
				performed[#performed + 1] = "menu.keybinds"
			end
		end,
	}
	for _, name in ipairs(KEYMAPS) do
		require("keymaps.global." .. name)
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
	return table.concat(flags, ",")
end

--- One text line per bind, sorted: config, key, label, flags, what the key dispatches.
local function dump_lines()
	local lines = {}
	for _, config in ipairs(CONFIGS) do
		load_keymaps(config)
		for _, entry in ipairs(binds) do
			performed = {}
			local ok, err = pcall(entry.action)
			local what = ok and table.concat(performed, ";") or ("ERROR " .. tostring(err))
			lines[#lines + 1] = table.concat({
				config.name,
				entry.key,
				entry.opts.desc or "-",
				flags_of(entry.opts) ~= "" and flags_of(entry.opts) or "-",
				what ~= "" and what or "-",
			}, "\t")
		end
	end
	table.sort(lines)
	return lines
end

if arg[1] == "--dump" then
	print(table.concat(dump_lines(), "\n"))
	os.exit(0)
end

local failures = 0
local function check(name, ok)
	if not ok then
		failures = failures + 1
		print("FAIL " .. name)
	end
end

-- The binds, key for key, against the fixture (comment lines start with #).
local expected = {}
for line in io.lines(here .. "/fixtures/act_global_binds.tsv") do
	if line ~= "" and line:sub(1, 1) ~= "#" then
		expected[#expected + 1] = line
	end
end
table.sort(expected)
local actual = dump_lines()
local expected_set, actual_set = {}, {}
for _, line in ipairs(expected) do
	expected_set[line] = true
end
for _, line in ipairs(actual) do
	actual_set[line] = true
end
for _, line in ipairs(expected) do
	check("missing bind: " .. line, actual_set[line])
end
for _, line in ipairs(actual) do
	check("unexpected bind: " .. line, expected_set[line])
end
check("bind count " .. #actual .. " vs " .. #expected, #actual == #expected)

-- The action ids, and that each runs by name with the same effect as its key.
load_keymaps(CONFIGS[1])
local Act = require("lib.act")
check("no warnings: " .. table.concat(Act.warnings, "; "), #Act.warnings == 0)
local ids = {}
for _, handle in ipairs(Act.list()) do
	ids[handle.id] = handle
end
local EXPECTED_IDS = {
	"help.keybinds",
	"window.close",
	"window.fullscreen",
	"window.maximize",
	"window.restore_closed",
	"window.focus",
	"window.move",
	"window.cycle_float",
	"scratchpad.toggle",
	"scratchpad.move",
	"monitor.focus",
	"monitor.move_window",
	"workspace.focus",
	"workspace.move",
	"workspace.cycle",
	"workspace.move_window",
	"media.prev",
	"media.next",
	"media.play_pause",
	"media.volume_up",
	"media.volume_down",
	"media.mute",
	"media.mute_mic",
	"media.brightness_up",
	"media.brightness_down",
}
for _, id in ipairs(EXPECTED_IDS) do
	check("defined: " .. id, ids[id] ~= nil)
end

local function ran(id, ...)
	performed = {}
	local ok, err = pcall(Act.run, id, ...)
	return ok and table.concat(performed, ";") or ("ERROR " .. tostring(err))
end
check("run window.focus left", ran("window.focus", "left") == "focus({direction=l})")
check("run window.move up", ran("window.move", "up") == "window.move({direction=u})")
check("run monitor.focus 2", ran("monitor.focus", 2) == "focus({monitor=MON2})")
check("run workspace.focus 3 (global)", ran("workspace.focus", 3) == "focus({workspace=3})")
check("run workspace.cycle prev (global)", ran("workspace.cycle", "prev") == "focus({workspace=e-1})")
check("run media.mute", ran("media.mute") == "exec_cmd(wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle)")
check("run bad direction fails", ran("window.focus", "sideways"):match("^ERROR") ~= nil)
-- The same ids follow Config.persistent_workspaces at run time, not at load time.
package.loaded["config"].persistent_workspaces = true
check("run workspace.focus 3 (persistent)", ran("workspace.focus", 3) == "focus({workspace=m~3})")
check("run workspace.cycle next (persistent)", ran("workspace.cycle", "next") == "focus({workspace=m+1})")
check(
	"run workspace.move_window prev (persistent)",
	ran("workspace.move_window", "prev") == "window.move({workspace=m-1})"
)

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("act global: all passed")
