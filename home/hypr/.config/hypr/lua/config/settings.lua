-- hypr/.config/hypr/lua/config/settings.lua
-- Centralized settings and constants

local Settings = {}

-- Timing delays (in seconds)
Settings.DELAYS = {
	workspace_preload = 0.1, -- Delay between workspace preloads
	between_launches = 0.1, -- Delay between app launches
	menu_focus = 0.1, -- Delay after focusing workspace for menu
}

-- Timeouts (in seconds)
Settings.TIMEOUTS = {
	firefox_windows = 10, -- Wait for Firefox windows to appear
	window_count = 10, -- Wait for expected window count
	app_launch = 5, -- Generic app launch timeout
	graphics_ready = 10, -- Wait for graphics system
}

-- Window classes for application detection
Settings.WINDOW_CLASSES = {
	firefox = "org.mozilla.firefox",
	chrome = "google-chrome",
	chromium = "chromium-browser",
	brave = "brave-browser",
	edge = "microsoft-edge",
}

-- Application command patterns
Settings.APP_PATTERNS = {
	firefox = "^firefox",
	flatpak = "^flatpak run",
	chrome = "^google%-chrome",
	chromium = "^chromium",
}

-- Multi-window applications (need special handling)
Settings.MULTI_WINDOW_APPS = {
	"firefox",
	"chrome",
	"chromium",
	"brave",
}

return Settings
