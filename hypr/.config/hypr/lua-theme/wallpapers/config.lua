-- hypr/.config/hypr/lua-theme/wallpapers/config.lua
-- Configuration for the day/night wallpaper rotator.
-- Adjust paths to your own collections. Leave values as nil to use defaults.

local home = os.getenv("HOME") or ""

return {
	-- Rotation cadence
	interval_minutes = 1,

	-- Default directories (per period)
	default_wallpaper_dir = home .. "/Pictures/Wallpapers/Pixel Art",
	dirs = {
		morning = home .. "/Pictures/Wallpapers/Pixel Art/Morning", -- DIR_MORNING
		day = home .. "/Pictures/Wallpapers/Pixel Art/Day", -- DIR_DAY
		evening = home .. "/Pictures/Wallpapers/Pixel Art/Evening", -- DIR_EVENING
		night = home .. "/Pictures/Wallpapers/Pixel Art/Night", -- DIR_NIGHT
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
