-- Prints every bind the shipped keymaps register, one JSON object per line: {submap, key, desc, opts, action}.
-- `action` is the manifest id when the bind came from Bind.action, else null. It loads keymaps/init.lua under a
-- permissive stub `hl` and a fixed default Config (leader SUPER, no machine file, no custom/), so the result is the
-- same on every machine.
--
--   lua home/hypr/tests/bind_dump.lua [--keymap FILE] [--compare FILE]
--
-- --keymap loads FILE instead of keymaps/init.lua (tests). --compare prints the lines only one side has and exits 1
-- when the dump differs from FILE, a dump saved earlier. A new `require` the stubs lack fails with the module name.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
local hypr_dir = here .. "/../.config/hypr"
package.path = hypr_dir .. "/?.lua;" .. hypr_dir .. "/?/init.lua;" .. package.path

local keymap_file, compare_file
local i = 1
while i <= #arg do
	if arg[i] == "--keymap" then
		keymap_file, i = arg[i + 1], i + 2
	elseif arg[i] == "--compare" then
		compare_file, i = arg[i + 1], i + 2
	else
		io.stderr:write("usage: bind_dump.lua [--keymap FILE] [--compare FILE]\n")
		os.exit(2)
	end
end

--- A value that accepts any field access and any call, so module code can run without its real dependency.
--- Calling one returns a tagged table naming the path, which is how a dispatcher shows in `action`-less rows.
local function proxy(path)
	return setmetatable({}, {
		__index = function(_, name)
			return proxy(path .. "." .. tostring(name))
		end,
		__call = function()
			return { dsp = path }
		end,
	})
end

local current_submap = ""
local rows = {}
local handle_rows = {}

_G.hl = setmetatable({
	version = function()
		return "0.57.0"
	end,
	bind = function(key, action, opts)
		local row = { submap = current_submap, key = key, desc = opts and opts.desc, opts = {} }
		for name, value in pairs(opts or {}) do
			if name ~= "desc" then
				row.opts[name] = value
			end
		end
		rows[#rows + 1] = row
		local handle = {}
		handle_rows[handle] = row
		return handle
	end,
	define_submap = function(name, reset, body)
		if body == nil then
			body = reset
		end
		local previous = current_submap
		current_submap = name
		body()
		current_submap = previous
	end,
	get_config = function() end,
	get_monitors = function()
		return {}
	end,
	get_current_submap = function()
		return ""
	end,
	dsp = proxy("hl.dsp"),
}, {
	__index = function(_, name)
		return proxy("hl." .. name)
	end,
})

-- Modules that reach the running session or optional repos; nothing in a keymap needs their real behaviour at load.
for _, name in ipairs({
	"lua.plugins.hyprvim",
	"config.rules",
	"config.autostart",
	"extensions.auto_launcher.launcher",
}) do
	package.loaded[name] = proxy(name)
end

-- The repo defaults with the derived fields set by hand: Config.merge would probe the machine (terminal, laptop
-- panel, NVIDIA) and write a terminal wrapper into the state dir.
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
Config.monitors = {}

local Bind = require("lib.key.bind")
Bind.manifest_dir = here .. "/../../oasis-djinn/.config/oasis-djinn"
Bind.djinn_bin = "/bin/sh" -- the runner counts as installed, so ipc and command actions dump as `oasis-djinn <id>`

local loaded, err = xpcall(function()
	if keymap_file then
		dofile(keymap_file)
	else
		require("keymaps")
	end
end, debug.traceback)
if not loaded then
	io.stderr:write("bind_dump: loading the keymaps failed (a new require may need a stub here):\n" .. err .. "\n")
	os.exit(1)
end
if #Bind.warnings > 0 then
	io.stderr:write("bind_dump: Bind.action warned:\n" .. table.concat(Bind.warnings, "\n") .. "\n")
	os.exit(1)
end

local Json = require("lib.json")
for handle, row in pairs(handle_rows) do
	row.action = Bind.action_ids[handle]
end
local lines = {}
for _, row in ipairs(rows) do
	-- Functions and proxies have no stable text; the dump keeps what identifies a bind, not what it calls.
	local opts = {}
	for name, value in pairs(row.opts) do
		if type(value) ~= "table" and type(value) ~= "function" then
			opts[name] = value
		end
	end
	local line = Json.encode({ submap = row.submap, key = row.key, desc = row.desc or "", opts = opts })
	-- Json.encode drops nil fields, so null is written by hand to keep every row the same shape.
	lines[#lines + 1] = line:sub(1, -2) .. ',"action":' .. (row.action and Json.encode(row.action) or "null") .. "}"
end

if not compare_file then
	for _, line in ipairs(lines) do
		print(line)
	end
	os.exit(0)
end

local saved = {}
for line in assert(io.open(compare_file)):lines() do
	saved[#saved + 1] = line
end
--- Prints each line of `from` that `other` lacks (counting repeats), prefixed with `mark`; true when any.
local function missing_from(from, other, mark)
	local left = {}
	for _, line in ipairs(other) do
		left[line] = (left[line] or 0) + 1
	end
	local any = false
	for _, line in ipairs(from) do
		if (left[line] or 0) > 0 then
			left[line] = left[line] - 1
		else
			print(mark .. line)
			any = true
		end
	end
	return any
end
local removed = missing_from(saved, lines, "- ")
local added = missing_from(lines, saved, "+ ")
os.exit((removed or added) and 1 or 0)
