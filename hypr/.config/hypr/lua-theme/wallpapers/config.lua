-- hypr/.config/hypr/lua-theme/wallpapers/config.lua
-- Configuration for the wallpaper system.
-- Adjust paths to your own collections. Leave values as nil to use defaults.

local home = os.getenv("HOME") or ""

return {
	-- Feature toggles
	rotation_enabled = true, -- Set to false to apply wallpaper once and exit
	time_of_day_enabled = true, -- Set to false to use only default_wallpaper_dir (no period switching)

	-- Rotation settings
	interval_minutes = 15, -- Rotation cadence (only used when rotation_enabled = true)

	-- Wallpaper directories
	default_wallpaper_dir = home .. "/Pictures/Wallpapers/Pixel Art", -- Default/fallback directory

	-- Specify directories to use based on time of day (only used when time_of_day_enabled = true)
	dirs = {
		morning = home .. "/Pictures/Wallpapers/Pixel Art/Morning",
		day = home .. "/Pictures/Wallpapers/Pixel Art/Day",
		evening = home .. "/Pictures/Wallpapers/Pixel Art/Evening",
		night = home .. "/Pictures/Wallpapers/Pixel Art/Night",
	},

	-- Static period start hours (24h integers, only used when time_of_day_enabled = true)
	-- Overridden when location_enabled is also true
	start_hours = {
		morning = 6,
		day = 11,
		evening = 16,
		night = 19,
	},

	-- Location controls (only used when time_of_day_enabled = true)
	location_enabled = true,
	refresh_interval_seconds = 4 * 60 * 60, -- 4 hours
	manual_lat = nil, -- set to a number, e.g., 40.7128
	manual_lon = nil, -- set to a number, e.g., -74.0060

	-- Logging
	verbose = false,
}
