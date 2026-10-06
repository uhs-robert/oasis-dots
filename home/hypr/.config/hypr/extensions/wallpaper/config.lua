-- home/hypr/.config/hypr/extensions/wallpaper/config.lua
-- Configuration for the wallpaper system.
-- Adjust paths to your own collections. Leave values as nil to use defaults.

local home = os.getenv("HOME") or ""
local cache_home = os.getenv("XDG_CACHE_HOME") or (home .. "/.cache")

return {
  -- Feature toggles
  rotation_enabled = true, -- Set to false to apply wallpaper once and exit
  rotation = true, -- Set to false to keep the process alive without timed rotation (Settings page toggle)
  time_of_day_enabled = true, -- Set to false to rotate through every image in wallpaper_dir
  seasons_enabled = true, -- Set to false to use only the Any season (only used when time_of_day_enabled = true)
  weather_enabled = true, -- Set to false to skip weather folders (only used when time_of_day_enabled = true)

  -- Rotation settings
  interval_minutes = 15, -- Rotation cadence (only used when rotation_enabled = true)
  history_size = 12, -- Recently shown wallpapers to avoid repeating; 0 allows repeats

  -- Layout: <Season>/<Period>/<Weather>/ with Season Any|Spring|Summer|Fall|Winter,
  -- Period Dawn|Day|Evening|Night and an optional Weather Rain|Snow|Cloudy
  wallpaper_dir = home .. "/Pictures/Wallpapers/Pixel Art",

  -- Month each season starts (northern hemisphere; flipped when the latitude is southern)
  season_start_months = {
    spring = 3,
    summer = 6,
    fall = 9,
    winter = 12,
  },

  -- Weather
  weather_chance = 0.6, -- Odds that each monitor shows a weather wallpaper while one matches
  weather_cache = cache_home .. "/quickshell/weather.json", -- Written by the Quickshell bar
  weather_max_age_minutes = 60, -- Ignore the cache when the bar has not refreshed it for this long

  -- Static period start hours (24h integers, only used when time_of_day_enabled = true)
  -- Overridden when location_enabled is also true
  start_hours = {
    dawn = 6,
    day = 11,
    evening = 16,
    night = 19,
  },

  -- Location controls (only used when time_of_day_enabled = true)
  location_enabled = false, -- true follows the sun; goes online (ipinfo.io, open-meteo.com) only without a fresh Quickshell cache
  refresh_interval_seconds = 4 * 60 * 60, -- 4 hours
  manual_lat = nil, -- set to a number, e.g., 40.7128
  manual_lon = nil, -- set to a number, e.g., -74.0060

  -- Logging
  verbose = false,
}
