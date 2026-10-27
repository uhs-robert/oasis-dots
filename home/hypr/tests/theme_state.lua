-- Runs theme/init.lua against stubbed generators and a temp HOME and checks how it picks the theme at load: the state
-- file wins; without one (first run) it takes the legacy ~/.config/hypr/theme/.current_theme, else keeps the default,
-- and writes the state file either way so Quickshell has a file to watch.
--
--   lua home/hypr/tests/theme_state.lua
local here = arg[0]:match("^(.*)/[^/]*$") or "."
local hypr_dir = here .. "/../.config/hypr"
package.path = hypr_dir .. "/?.lua;" .. hypr_dir .. "/?/init.lua;" .. package.path

local DEFAULT_THEME = "oasis_moonlight"

local mktemp = assert(io.popen("mktemp -d"))
local work = mktemp:read("*line")
mktemp:close()
assert(work and work ~= "", "mktemp -d gave no directory")

local home = work .. "/home"
local state_file = home .. "/.local/state/hypr/theme"
local legacy_file = home .. "/.config/hypr/theme/.current_theme"

-- No XDG_STATE_HOME, so lib.state falls back to HOME and the state file lands under the temp HOME.
local real_getenv = os.getenv
---@diagnostic disable-next-line: duplicate-set-field
os.getenv = function(name)
	if name == "HOME" then
		return home
	end
	if name == "XDG_STATE_HOME" then
		return nil
	end
	return real_getenv(name)
end

local function read(path)
	local file = io.open(path, "r")
	if not file then
		return nil
	end
	local text = file:read("*a")
	file:close()
	return text
end

local function write(path, text)
	assert(os.execute("mkdir -p '" .. path:match("^(.*)/[^/]*$") .. "'"))
	local file = assert(io.open(path, "w"))
	file:write(text)
	file:close()
end

--- Loads theme/init.lua fresh in a clean HOME seeded with `files` (path -> contents) and returns the stub Config.
local function load_theme(files)
	assert(os.execute("rm -rf '" .. home .. "'"))
	for path, text in pairs(files) do
		write(path, text)
	end
	local config = { theme = DEFAULT_THEME }
	package.loaded["config"] = config
	package.loaded["theme.generate"] = { all = function() end }
	package.loaded["lib.missing_repos"] = { add = function() end }
	assert(loadfile(hypr_dir .. "/theme/init.lua"))()
	return config
end

local failures = 0
local function expect(name, actual, wanted)
	if actual ~= wanted then
		failures = failures + 1
		io.stderr:write(("FAIL %s: got %s, want %s\n"):format(name, tostring(actual), tostring(wanted)))
	end
end

local config = load_theme({ [state_file] = "saved_theme\n", [legacy_file] = "legacy_theme\n" })
expect("a saved theme is restored", config.theme, "saved_theme")
expect("a restored state file is left as it was", read(state_file), "saved_theme\n")

config = load_theme({ [legacy_file] = "legacy_theme\n" })
expect("the first run takes the legacy theme", config.theme, "legacy_theme")
expect("the first run writes the legacy theme to the state file", read(state_file), "legacy_theme")

config = load_theme({})
expect("the first run without a legacy file keeps the default", config.theme, DEFAULT_THEME)
expect("the first run writes the default to the state file", read(state_file), DEFAULT_THEME)

config = load_theme({ [state_file] = "\n", [legacy_file] = "legacy_theme\n" })
expect("an empty state file counts as a first run", config.theme, "legacy_theme")
expect("an empty state file is rewritten", read(state_file), "legacy_theme")

os.execute("rm -rf '" .. work .. "'")
if failures > 0 then
	os.exit(1)
end
print("theme state: all passed")
