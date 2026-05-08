-- hypr/.config/hypr/lua/lib/wait.lua
-- Reusable timeout and polling utilities

local Logger = require("lib.logger")
local Hyprctl = require("lib.hyprctl")
local Utils = require("lib.utils")
local Settings = require("config.settings")

local Wait = {}

-- Generic wait for condition with timeout
-- check_fn: function that returns true when condition is met
-- timeout: maximum seconds to wait
-- interval: seconds between checks (default 1)
-- Returns: true if condition met, false if timeout
function Wait.for_condition(check_fn, timeout, interval)
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

-- Wait for windows by window class
-- class: window class to look for (e.g., "org.mozilla.firefox")
-- expected_count: number of windows expected
-- timeout: maximum seconds to wait (default from settings)
-- Returns: array of window addresses, or empty array if timeout
function Wait.for_windows_by_class(class, expected_count, timeout)
	timeout = timeout or Settings.TIMEOUTS.firefox_windows
	local elapsed = 0
	local windows = {}

	Logger.debug(string.format("Waiting for %d windows of class '%s'...", expected_count, class))

	while elapsed < timeout do
		local clients_json = Hyprctl.clients()
		if clients_json then
			local query = string.format('.[] | select(.class=="%s") | .address', class)
			windows = Hyprctl.query_json_lines(clients_json, query)

			Logger.debug(string.format("Found %d of %d expected windows", #windows, expected_count))

			if #windows >= expected_count then
				Logger.info(string.format("Found %d windows of class '%s'", #windows, class))
				return windows
			end
		end

		Utils.sleep(1)
		elapsed = elapsed + 1
	end

	Logger.warn(
		string.format("Timeout: only found %d of %d expected windows of class '%s'", #windows, expected_count, class)
	)
	return windows
end

-- Wait for total window count to reach expected
-- expected_count: total number of windows expected
-- timeout: maximum seconds to wait (default from settings)
-- Returns: true if count reached, false if timeout
function Wait.for_window_count(expected_count, timeout)
	timeout = timeout or Settings.TIMEOUTS.window_count
	Logger.info(string.format("Waiting for %d windows to appear...", expected_count))

	local check_fn = function()
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

	local success = Wait.for_condition(check_fn, timeout, 1)

	if not success then
		Logger.warn(string.format("Timeout: expected %d windows", expected_count))
	end

	return success
end

-- Wait with exponential backoff
-- check_fn: function to check condition
-- initial_delay: starting delay in seconds
-- max_delay: maximum delay between checks
-- timeout: maximum total time to wait
-- Returns: true if condition met, false if timeout
function Wait.with_exponential_backoff(check_fn, initial_delay, max_delay, timeout)
	local delay = initial_delay
	local elapsed = 0

	while elapsed < timeout do
		if check_fn() then
			return true
		end

		Utils.sleep(delay)
		elapsed = elapsed + delay

		-- Double the delay up to max
		delay = math.min(delay * 2, max_delay)
	end

	return false
end

return Wait
