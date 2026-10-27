-- Loads every lib/actions/defs/*.lua headlessly and prints the action list (Act.list_json) on stdout. It exits 1 on
-- any Act warning, so lib/check/steps/registry.py can check what the definitions refer to (ids, IPC functions,
-- scripts) and throw the list away: nothing about the actions is committed. Runs under a permissive `hl` and the repo's
-- default Config, so the output is the same on every machine. A new `require` the stubs lack fails with its module name.
--
--   lua home/hypr/tests/act_refs.lua [--defs DIR] [--resolve ID [WORD...]]
--
-- --defs reads DIR instead of lib/actions/defs (the tests plant bad definitions there).
-- --resolve prints one JSON object, the `perform` plan of Act.resolve (what `hypr-act ID WORD...` would run, with the
-- params checked the same way), instead of the list; an Act error exits 5 with its message, as hypr-act does.
-- shadow.sh action uses it, since the shadow's Hyprland has no actions of its own.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
local hypr_dir = here .. "/../.config/hypr"
package.path = hypr_dir .. "/?.lua;" .. hypr_dir .. "/?/init.lua;" .. package.path

local defs_dir = hypr_dir .. "/lib/actions/defs"
local first = 1
if arg[1] == "--defs" and arg[2] then
	defs_dir = arg[2]
	first = 3
end
local resolve_id, resolve_words
if arg[first] == "--resolve" and arg[first + 1] then
	resolve_id = arg[first + 1]
	resolve_words = { table.unpack(arg, first + 2) }
elseif #arg >= first then
	io.stderr:write("usage: act_refs.lua [--defs DIR] [--resolve ID [WORD...]]\n")
	os.exit(2)
end

--- A value that accepts any field access and any call, so module code can run without its real dependency.
local function proxy()
	return setmetatable({}, {
		__index = function()
			return proxy()
		end,
		__call = function()
			return proxy()
		end,
	})
end

_G.hl = setmetatable({
	version = function()
		return "0.57.0"
	end,
	bind = function()
		return { remove = function() end }
	end,
	timer = function() end,
	notification = { create = function() end },
	get_config = function() end,
	get_monitors = function()
		return {}
	end,
	get_current_submap = function()
		return ""
	end,
}, {
	__index = function()
		return proxy()
	end,
})

-- Modules that reach the running session or optional repos; a definition file needs none of their behaviour at load.
for _, name in ipairs({
	"lua.plugins.hyprvim",
	"config.rules",
	"config.autostart",
	"extensions.auto_launcher.launcher",
}) do
	package.loaded[name] = proxy()
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

local Act = require("lib.act")

local listing = assert(io.popen('ls -1 "' .. defs_dir .. '"/*.lua 2>/dev/null'))
local files = {}
for path in listing:lines() do
	files[#files + 1] = path
end
listing:close()
table.sort(files)
if #files == 0 then
	io.stderr:write("act_refs: no definition files in " .. defs_dir .. "\n")
	os.exit(1)
end
for _, path in ipairs(files) do
	assert(loadfile(path))()
end

if #Act.warnings > 0 then
	for _, warning in ipairs(Act.warnings) do
		io.stderr:write("act_refs: " .. warning .. "\n")
	end
	os.exit(1)
end
if resolve_id then
	local ok, handle_or_message, _, plan = pcall(Act.resolve, resolve_id, resolve_words)
	if not ok then
		io.stderr:write(tostring(handle_or_message) .. "\n")
		os.exit(5)
	end
	local Json = require("lib.json")
	for _, field in ipairs({ "args", "argv" }) do
		if plan[field] then
			plan[field] = Json.array(plan[field])
		end
	end
	print(Json.encode(plan))
	os.exit(0)
end
print(Act.list_json())
