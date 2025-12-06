-- hypr/.config/hypr/lua-theme/wallpapers/config.lua
-- Configuration for the day/night wallpaper rotator.
-- Adjust paths to your own collections. Leave values as nil to use defaults.

local home = os.getenv("HOME") or ""

return {
	interval_minutes = 15, -- Rotation cadence
	default_wallpaper_dir = home .. "/Pictures/Wallpapers/Pixel Art", -- Default directories (per period)

	-- Specify directories to use based on time of day
	dirs = {
		morning = home .. "/Pictures/Wallpapers/Pixel Art/Morning",
		day = home .. "/Pictures/Wallpapers/Pixel Art/Day",
		evening = home .. "/Pictures/Wallpapers/Pixel Art/Evening",
		night = home .. "/Pictures/Wallpapers/Pixel Art/Night",
	},

	-- Static period start hours (24h integers). Overridden when location is enabled.
	start_hours = {
		morning = 6,
		day = 11,
		evening = 16,
		night = 19,
	},

	-- Location controls
	location_enabled = true,
	refresh_interval_seconds = 4 * 60 * 60, -- 4 hours
	manual_lat = nil, -- set to a number, e.g., 40.7128
	manual_lon = nil, -- set to a number, e.g., -74.0060

	-- Logging
	verbose = false,
}
