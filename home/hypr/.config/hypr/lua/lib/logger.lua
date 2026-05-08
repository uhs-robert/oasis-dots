-- hypr/.config/hypr/lua/lib/logger.lua
-- Unified logging to systemd journal and stderr

local Logger = {}

-- Configuration
Logger.tag = "hypr-lua"
Logger.levels = {
	DEBUG = "debug",
	INFO = "info",
	WARN = "warn",
	ERROR = "error",
}

-- Format a log message with timestamp
local function format_message(level, message)
	local timestamp = os.date("%Y-%m-%d %H:%M:%S")
	return string.format("[%s] [%s] %s", timestamp, level:upper(), message)
end

-- Write to systemd journal using logger command
local function write_to_journal(tag, level, message)
	local priority = ({
		debug = "debug",
		info = "info",
		warn = "warning",
		error = "err",
	})[level] or "info"

	-- Use logger command to write to systemd journal
	local cmd = string.format('logger -t "%s" -p user.%s "%s"', tag, priority, message:gsub('"', '\\"'))
	os.execute(cmd)
end

-- Write to stderr
local function write_to_stderr(formatted_message)
	io.stderr:write(formatted_message .. "\n")
	io.stderr:flush()
end

-- Generic log function
local function log(level, message)
	local formatted = format_message(level, message)
	write_to_stderr(formatted)
	write_to_journal(Logger.tag, level, message)
end

-- Public API
function Logger.set_tag(tag)
	Logger.tag = tag
end

function Logger.debug(message)
	log(Logger.levels.DEBUG, message)
end

function Logger.info(message)
	log(Logger.levels.INFO, message)
end

function Logger.warn(message)
	log(Logger.levels.WARN, message)
end

function Logger.error(message)
	log(Logger.levels.ERROR, message)
end

-- Convenience alias (matches bash scripts' "log" function)
Logger.log = Logger.info

return Logger
