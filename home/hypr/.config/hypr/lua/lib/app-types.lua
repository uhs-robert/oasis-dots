-- hypr/.config/hypr/lua/lib/app-types.lua
-- Application type detection and classification

local Settings = require("config.settings")

local AppTypes = {}

-- Check if command is Firefox
function AppTypes.is_firefox(cmd)
	return cmd == "firefox" or cmd:match(Settings.APP_PATTERNS.firefox)
end

-- Check if command is a flatpak application
function AppTypes.is_flatpak(cmd)
	return cmd:match(Settings.APP_PATTERNS.flatpak) ~= nil
end

-- Check if command is Chrome
function AppTypes.is_chrome(cmd)
	return cmd:match(Settings.APP_PATTERNS.chrome) ~= nil
end

-- Check if command is Chromium
function AppTypes.is_chromium(cmd)
	return cmd:match(Settings.APP_PATTERNS.chromium) ~= nil
end

-- Check if app needs multi-window handling
function AppTypes.is_multi_window(cmd)
	for _, app in ipairs(Settings.MULTI_WINDOW_APPS) do
		if cmd:match("^" .. app) then
			return true
		end
	end
	return false
end

-- Get window class for an application command
-- Returns the window class string or nil if unknown
function AppTypes.get_window_class(cmd)
	if AppTypes.is_firefox(cmd) then
		return Settings.WINDOW_CLASSES.firefox
	elseif AppTypes.is_chrome(cmd) then
		return Settings.WINDOW_CLASSES.chrome
	elseif AppTypes.is_chromium(cmd) then
		return Settings.WINDOW_CLASSES.chromium
	end
	return nil
end

-- Detect app type from command
-- Returns: "firefox", "flatpak", "chrome", "chromium", "generic"
function AppTypes.detect(cmd)
	if AppTypes.is_firefox(cmd) then
		return "firefox"
	elseif AppTypes.is_flatpak(cmd) then
		return "flatpak"
	elseif AppTypes.is_chrome(cmd) then
		return "chrome"
	elseif AppTypes.is_chromium(cmd) then
		return "chromium"
	else
		return "generic"
	end
end

return AppTypes
