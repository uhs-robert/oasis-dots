-- Runs theme/generate/desertfox.lua against a stub `desertfox` on PATH and a temp XDG_RUNTIME_DIR (never the real
-- socket): the push carries Config.theme, and a failing CLI, a missing CLI and a name with a quote all return cleanly.
--
--   lua home/hypr/tests/desertfox_generator.lua
local here = arg[0]:match("^(.*)/[^/]*$") or "."
local hypr_dir = here .. "/../.config/hypr"
package.path = hypr_dir .. "/?.lua;" .. hypr_dir .. "/?/init.lua;" .. package.path

local mktemp = assert(io.popen("mktemp -d"))
local work = mktemp:read("*line")
mktemp:close()
assert(work and work ~= "", "mktemp -d gave no directory")
local bin, runtime, log = work .. "/bin", work .. "/run", work .. "/calls"
assert(os.execute("mkdir -p '" .. bin .. "' '" .. runtime .. "'"))

local real_getenv = os.getenv
local env = { XDG_RUNTIME_DIR = runtime, PATH = bin .. ":/usr/bin:/bin" }
---@diagnostic disable-next-line: duplicate-set-field
os.getenv = function(name)
	if env[name] ~= nil then
		return env[name]
	end
	return real_getenv(name)
end

-- os.execute inherits the real environment, so the stub run gets PATH and XDG_RUNTIME_DIR through a prefix.
local real_execute = os.execute
---@diagnostic disable-next-line: duplicate-set-field
os.execute = function(cmd)
	return real_execute(
		"env PATH='"
			.. env.PATH
			.. "' XDG_RUNTIME_DIR='"
			.. runtime
			.. "' "
			.. "sh -c '"
			.. cmd:gsub("'", "'\\''")
			.. "'"
	)
end

local function write_stub(body)
	local file = assert(io.open(bin .. "/desertfox", "w"))
	file:write("#!/bin/sh\n" .. body .. "\n")
	file:close()
	assert(real_execute("chmod +x '" .. bin .. "/desertfox'"))
end

local function read_log()
	local file = io.open(log, "r")
	if not file then
		return nil
	end
	local text = file:read("*a")
	file:close()
	return text
end

-- The push is a background job, so poll for the stub's log.
local function wait_for_log()
	for _ = 1, 50 do
		local text = read_log()
		if text then
			return text
		end
		real_execute("sleep 0.1")
	end
end

local Config = require("config")
local generate = require("theme.generate.desertfox")
local failures = 0
local function check(label, ok)
	if not ok then
		failures = failures + 1
		io.stderr:write("FAIL " .. label .. "\n")
	end
end

-- 1. The stub receives `theme <name>` and the runtime dir.
Config.theme = "oasis_moonlight"
write_stub('echo "$XDG_RUNTIME_DIR $*" > \'' .. log .. "'")
check("generator returns", pcall(generate, {}))
check("push sends theme name", wait_for_log() == runtime .. " theme oasis_moonlight\n")

-- 2. A failing CLI (no socket) does not raise.
os.remove(log)
write_stub("echo called > '" .. log .. "'; echo 'no socket' >&2; exit 1")
check("failing cli does not raise", pcall(generate, {}))
check("failing cli was still called", wait_for_log() == "called\n")

-- 3. No CLI on PATH: nothing runs, nothing raises.
os.remove(log)
os.remove(bin .. "/desertfox")
check("missing cli does not raise", pcall(generate, {}))
real_execute("sleep 0.5")
check("missing cli runs nothing", read_log() == nil)

-- 4. A quote in the name stays one argument.
write_stub("printf '%s\\n' \"$2\" > '" .. log .. "'")
Config.theme = "it's"
check("quoted name does not raise", pcall(generate, {}))
check("quoted name arrives whole", wait_for_log() == "it's\n")

-- 5. On the embedded fallback palette the push names oasis_moonlight, not the missing saved name.
os.remove(log)
write_stub("printf '%s\\n' \"$2\" > '" .. log .. "'")
Config.theme = "oasis_gone"
check("fallback does not raise", pcall(generate, require("theme.fallback")))
check("fallback pushes oasis_moonlight", wait_for_log() == "oasis_moonlight\n")

-- 6. Generate.all really runs the desertfox generator (registration, not just the generator).
os.remove(log)
write_stub("printf '%s\\n' \"$2\" > '" .. log .. "'")
Config.theme = "oasis_moonlight"
local Generate = require("theme.generate")
for name in pairs(Generate) do
	if name ~= "all" and name ~= "desertfox" then
		Generate[name] = function() end
	end
end
Generate.all({})
check("Generate.all runs desertfox", wait_for_log() == "oasis_moonlight\n")

-- 7. A missing theme does not raise.
Config.theme = nil
check("nil theme does not raise", pcall(generate, {}))

real_execute("rm -rf '" .. work .. "'")
if failures > 0 then
	os.exit(1)
end
print("ok desertfox generator")
