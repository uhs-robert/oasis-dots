-- hypr/.config/hypr/lua/lib/process.lua
-- Process management: PID files, duplicate detection, signal handling

local Logger = require("lib.logger")
local Utils = require("lib.utils")

local Process = {}

-- Get the runtime directory for PID files
local function get_runtime_dir()
	return os.getenv("XDG_RUNTIME_DIR") or "/tmp"
end

-- Get PID file path for a given process name
local function get_pid_file(name)
	return get_runtime_dir() .. "/hypr-lua-" .. name .. ".pid"
end

-- Check if a PID is still running
local function is_pid_running(pid)
	-- Use kill -0 to check if process exists
	local result = os.execute(string.format("kill -0 %d 2>/dev/null", pid))
	return result == 0 or result == true -- Lua 5.1 vs 5.2+ compatibility
end

-- Read PID from file
local function read_pid(pid_file)
	local f = io.open(pid_file, "r")
	if not f then
		return nil
	end
	local pid = f:read("*n")
	f:close()
	return pid
end

-- Write PID to file
local function write_pid(pid_file, pid)
	local f = io.open(pid_file, "w")
	if not f then
		Logger.error("Failed to write PID file: " .. pid_file)
		return false
	end
	f:write(tostring(pid))
	f:close()
	return true
end

-- Remove PID file
local function remove_pid(pid_file)
	os.remove(pid_file)
end

-- Ensure only a single instance of a process is running
-- Returns: true if this is the only instance, false if another is running
function Process.ensure_single_instance(name)
	local pid_file = get_pid_file(name)
	local current_pid = tonumber(os.getenv("BASHPID")) or 0

	-- Check if PID file exists
	local existing_pid = read_pid(pid_file)
	if existing_pid then
		-- Check if that PID is still running
		if is_pid_running(existing_pid) then
			Logger.warn(string.format("%s already running with PID %d", name, existing_pid))
			return false
		else
			Logger.info(string.format("Stale PID file found for %s (PID %d not running)", name, existing_pid))
			remove_pid(pid_file)
		end
	end

	-- Write our PID
	write_pid(pid_file, current_pid)
	Logger.info(string.format("Started %s with PID %d", name, current_pid))

	-- Set up cleanup on exit
	Process.cleanup_on_exit(function()
		remove_pid(pid_file)
	end)

	return true
end

-- Register cleanup function to run on exit
-- Note: Lua doesn't have built-in signal handling like bash's trap
-- This is best-effort cleanup when script exits normally
function Process.cleanup_on_exit(cleanup_fn)
	-- Store cleanup function to be called at exit
	if not Process._cleanup_functions then
		Process._cleanup_functions = {}
	end
	table.insert(Process._cleanup_functions, cleanup_fn)
end

-- Call all registered cleanup functions
function Process.run_cleanup()
	if Process._cleanup_functions then
		for _, fn in ipairs(Process._cleanup_functions) do
			local success, err = pcall(fn)
			if not success then
				Logger.error("Cleanup function failed: " .. tostring(err))
			end
		end
	end
end

-- Wait for a condition to become true, with timeout
-- check_fn: function that returns true when condition is met
-- timeout: maximum seconds to wait
-- interval: seconds between checks (default 1)
-- Returns: true if condition met, false if timeout
function Process.wait_for_condition(check_fn, timeout, interval)
	interval = interval or 1
	local elapsed = 0

	while elapsed < timeout do
		if check_fn() then
			return true
		end
		Utils.sleep(interval)
		elapsed = elapsed + interval
	end

	return false
end

-- Wait for a specific number of windows to appear (for app launching)
-- Returns: true if expected count reached, false if timeout
function Process.wait_for_window_count(expected_count, timeout)
	Logger.info(string.format("Waiting for %d windows to appear...", expected_count))

	local check_fn = function()
		local Hyprctl = require("lib.hyprctl")
		local clients_json = Hyprctl.clients()
		if not clients_json then
			return false
		end

		local count_str = Hyprctl.query_json(clients_json, ". | length")
		local count = tonumber(count_str) or 0

		if count >= expected_count then
			Logger.info(string.format("Detected %d windows of %d expected", count, expected_count))
			return true
		end

		return false
	end

	local success = Process.wait_for_condition(check_fn, timeout, 1)

	if not success then
		Logger.warn(string.format("Timeout waiting for windows (expected %d)", expected_count))
	end

	return success
end

-- Wait for graphics to be ready (for startup scripts)
function Process.wait_for_graphics(timeout)
	timeout = timeout or 10
	Logger.info("Waiting for graphics to be ready...")

	local check_fn = function()
		-- Check if hyprctl is responsive
		local handle = Utils.popen_assert("hyprctl monitors 2>&1")
		local output = handle:read("*a")
		handle:close()

		-- If we got output without error, graphics are ready
		return output and not output:match("error") and not output:match("No monitors")
	end

	local success = Process.wait_for_condition(check_fn, timeout, 0.5)

	if success then
		Logger.info("Graphics ready")
	else
		Logger.error("Graphics not ready after timeout")
	end

	return success
end

return Process
