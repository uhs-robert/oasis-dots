-- Loads lib/session_start.lua against a stubbed `hl` and a temp runtime dir and checks when its hooks run: on
-- hyprland.start at a normal first launch, after the reload when safe mode loads the config late, and never again on
-- an ordinary reload.
--
--   lua home/hypr/tests/session_start.lua
local here = arg[0]:match("^(.*)/[^/]*$") or "."
local hypr_dir = here .. "/../.config/hypr"

local mktemp = assert(io.popen("mktemp -d"))
local runtime = mktemp:read("*line")
mktemp:close()
assert(runtime and runtime ~= "", "mktemp -d gave no directory")

local SIGNATURE = "test_instance"
local marker = runtime .. "/hypr/" .. SIGNATURE .. "/dotfiles-session-started"
assert(os.execute("mkdir -p '" .. runtime .. "/hypr/" .. SIGNATURE .. "'"))

local real_getenv = os.getenv
---@diagnostic disable-next-line: duplicate-set-field
os.getenv = function(name)
	if name == "XDG_RUNTIME_DIR" then
		return runtime
	end
	if name == "HYPRLAND_INSTANCE_SIGNATURE" then
		return SIGNATURE
	end
	return real_getenv(name)
end

local handlers

--- Loads the module fresh, as a config (re)load does, registers one hook and returns how many times each event ran it.
local function load(monitor_count)
	handlers = {}
	local monitors = {}
	for i = 1, monitor_count do
		monitors[i] = { name = "M" .. i }
	end
	_G.hl = {
		get_monitors = function()
			return monitors
		end,
		on = function(event, fn)
			handlers[event] = handlers[event] or {}
			table.insert(handlers[event], fn)
		end,
	}
	local runs = 0
	assert(loadfile(hypr_dir .. "/lib/session_start.lua"))()(function()
		runs = runs + 1
	end)
	return function(event)
		for _, fn in ipairs(handlers[event] or {}) do
			fn()
		end
		return runs
	end
end

local function marked()
	local file = io.open(marker, "r")
	if file then
		file:close()
	end
	return file ~= nil
end

local failures = 0
local function expect(name, actual, wanted)
	if actual ~= wanted then
		failures = failures + 1
		io.stderr:write(("FAIL %s: got %s, want %s\n"):format(name, tostring(actual), tostring(wanted)))
	end
end

-- Under pcall so the temp dir is removed even when an assert fails or the module raises.
local ran, err = pcall(function()
	-- A normal first launch parses the config before any monitor exists, then fires config.reloaded and start.
	local fire = load(0)
	expect("first launch: config.reloaded does not run the hook", fire("config.reloaded"), 0)
	expect("first launch: hyprland.start runs the hook", fire("hyprland.start"), 1)
	expect("first launch: start leaves the marker", marked(), true)

	fire = load(3)
	expect("ordinary reload: config.reloaded does not run the hook", fire("config.reloaded"), 0)

	-- Safe mode: start fired for the recovery config, then "Load config" reloads this one with monitors up.
	os.remove(marker)
	fire = load(3)
	expect("late load: config.reloaded runs the hook", fire("config.reloaded"), 1)
	expect("late load: the reload leaves the marker", marked(), true)

	fire = load(3)
	expect("reload after a late load: the hook does not run again", fire("config.reloaded"), 0)
end)

assert(os.execute("rm -rf '" .. runtime .. "'"))
if not ran then
	io.stderr:write("FAIL " .. tostring(err) .. "\n")
	os.exit(1)
end
if failures > 0 then
	os.exit(1)
end
print("session_start: ok")
