-- hypr/.config/hypr/lua/lib/utils.lua
-- Shared utility functions for Lua scripts

local Utils = {}

-- Wrapper for io.popen that shows a notification on error and asserts
function Utils.popen_assert(cmd)
	local handle, err = io.popen(cmd)
	if not handle then
		local msg = "popen failed for command:\\n" .. cmd .. "\\nError: " .. tostring(err)
		os.execute('notify-send "Lua Script Error" "' .. msg .. '"')
		assert(handle, err)
	end
	return handle
end

-- Safe file writing with error handling
function Utils.write_file(path, content)
	local file = io.open(path, "w")
	if not file then
		print("Error: Could not write to " .. path)
		return false
	end
	file:write(content)
	file:close()
	return true
end

-- Safe file reading with error handling
function Utils.read_file(path)
	local file = io.open(path, "r")
	if not file then
		return nil, "Could not read file: " .. path
	end
	local content = file:read("*a")
	file:close()
	return content
end

-- Load a Lua file and return its result (useful for config files)
function Utils.load_lua_file(path)
	local chunk, err = loadfile(path)
	if not chunk then
		print("Error: Could not load Lua file: " .. path)
		print("Error: " .. tostring(err))
		return nil
	end
	return chunk()
end

-- Check if a file exists
function Utils.file_exists(path)
	local file = io.open(path, "r")
	if file then
		file:close()
		return true
	end
	return false
end

-- Execute a command and return success status
function Utils.execute(cmd)
	local result = os.execute(cmd)
	-- Lua 5.1 returns exit code directly, 5.2+ returns true/nil, exit code, signal
	if type(result) == "number" then
		return result == 0
	else
		return result == true or result == 0
	end
end

-- Sleep for a number of seconds (can be fractional)
function Utils.sleep(seconds)
	os.execute(string.format("sleep %s", tostring(seconds)))
end

-- Escape string for use in shell commands
function Utils.shell_escape(str)
	-- Escape single quotes and wrap in single quotes
	return "'" .. str:gsub("'", "'\\''") .. "'"
end

-- Split string by delimiter
function Utils.split(str, delimiter)
	local result = {}
	local pattern = string.format("([^%s]+)", delimiter)
	for match in str:gmatch(pattern) do
		table.insert(result, match)
	end
	return result
end

-- Trim whitespace from string
function Utils.trim(str)
	return str:match("^%s*(.-)%s*$")
end

return Utils
