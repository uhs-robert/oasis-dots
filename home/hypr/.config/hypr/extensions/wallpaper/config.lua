-- home/hypr/.config/hypr/extensions/wallpaper/config.lua
-- Configuration for the wallpaper system.
-- Adjust paths to your own collections. Leave values as nil to use defaults.

local home = os.getenv("HOME") or ""
local base = home .. "/Pictures/Wallpapers/Pixel Art"
local cache_home = os.getenv("XDG_CACHE_HOME") or (home .. "/.cache")

--- @param root string
local function period_dirs(root)
  return {
    morning = root .. "/Morning",
    day = root .. "/Day",
    evening = root .. "/Evening",
    night = root .. "/Night",
  }
end

return {
  -- Feature toggles
  rotation_enabled = true, -- Set to false to apply wallpaper once and exit
  time_of_day_enabled = true, -- Set to false to use only default_wallpaper_dir (no period switching)
  seasons_enabled = true, -- Set to false to ignore season_dirs (only used when time_of_day_enabled = true)
  weather_enabled = true, -- Set to false to ignore weather_dirs (only used when time_of_day_enabled = true)

  -- Rotation settings
  interval_minutes = 15, -- Rotation cadence (only used when rotation_enabled = true)

  -- Wallpaper directories
  default_wallpaper_dir = base, -- Default/fallback directory

  -- Specify directories to use based on time of day in every season (only used when time_of_day_enabled = true)
  dirs = period_dirs(base .. "/All"),

  -- Season directories, added to the time-of-day pool only while that season is current
  season_dirs = {
    spring = period_dirs(base .. "/Spring"),
    summer = period_dirs(base .. "/Summer"),
    autumn = period_dirs(base .. "/Autumn"),
    winter = period_dirs(base .. "/Winter"),
  },

  -- Month each season starts (northern hemisphere; flipped when the latitude is southern)
  season_start_months = {
    spring = 3,
    summer = 6,
    autumn = 9,
    winter = 12,
  },

  -- Weather directories, used at any time of day only while that weather is current
  weather_dirs = {
    rain = base .. "/Weather/Rain",
    snow = base .. "/Weather/Snow",
    storm = base .. "/Weather/Storm",
  },
  weather_chance = 0.6, -- Odds that each monitor shows a weather wallpaper while one matches
  weather_cache = cache_home .. "/quickshell/weather.json", -- Written by the Quickshell bar
  weather_max_age_minutes = 60, -- Ignore the cache when the bar has not refreshed it for this long

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
