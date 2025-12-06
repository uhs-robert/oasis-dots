-- hypr/.config/hypr/theme/wallpapers/lib/solar.lua
-- Coordinates + sunrise/sunset + period boundary calculation

local unpack = table.unpack or unpack

local Solar = {}

local function round_down_quarter(minute)
	return math.floor(minute / 15) * 15
end

local function valid_coord(x, minv, maxv)
	return x and x >= minv and x <= maxv
end

local function timezone_fallback(util)
	local tz = util.run_cmd("timedatectl show -p Timezone --value 2>/dev/null")
	if not tz then
		return 40.0, -74.0
	end
	tz = tz:match("([%w%/]+)")
	local map = {
		["America/New_York"] = { 40.7, -74.0 },
		["America/Detroit"] = { 40.7, -74.0 },
		["America/Toronto"] = { 40.7, -74.0 },
		["America/Chicago"] = { 41.8, -87.6 },
		["America/Winnipeg"] = { 41.8, -87.6 },
		["America/Denver"] = { 39.7, -104.9 },
		["America/Edmonton"] = { 39.7, -104.9 },
		["America/Los_Angeles"] = { 34.0, -118.2 },
		["America/Vancouver"] = { 34.0, -118.2 },
		["America/Phoenix"] = { 33.4, -112.0 },
		["Europe/London"] = { 51.5, -0.1 },
		["Europe/Paris"] = { 48.8, 2.3 },
		["Europe/Berlin"] = { 48.8, 2.3 },
		["Europe/Rome"] = { 48.8, 2.3 },
		["Europe/Moscow"] = { 55.7, 37.6 },
		["Asia/Tokyo"] = { 35.6, 139.6 },
		["Asia/Shanghai"] = { 31.2, 121.4 },
		["Asia/Hong_Kong"] = { 31.2, 121.4 },
		["Australia/Sydney"] = { -33.8, 151.2 },
	}
	return unpack(map[tz] or { 40.0, -74.0 })
end

local function ip_geolocate(util)
	local ip = util.run_cmd("curl -s --max-time 3 https://ipinfo.io/ip 2>/dev/null")
	if not ip or not ip:match("^%d+%.%d+%.%d+%.%d+$") then
		return nil
	end
	local loc = util.run_cmd("curl -s --max-time 3 https://ipinfo.io/" .. ip .. "/loc 2>/dev/null")
	if not loc then
		return nil
	end
	local lat, lon = loc:match("^(-?[%d%.]+),(-?[%d%.]+)")
	if lat and lon then
		return tonumber(lat), tonumber(lon)
	end
	return nil
end

local function sun_times_open_meteo(lat, lon, cfg, util)
	local url = string.format(
		"https://api.open-meteo.com/v1/forecast?latitude=%s&longitude=%s&daily=sunrise,sunset&timezone=auto",
		lat,
		lon
	)
	local json = util.run_cmd("curl -s --max-time 4 '" .. url .. "' 2>/dev/null")
	if not json then
		return nil
	end
	local sunrise = json:match('"sunrise"%s*:%s*%["([^"]+)"%]')
	local sunset = json:match('"sunset"%s*:%s*%["([^"]+)"%]')
	if not sunrise or not sunset then
		return nil
	end
	local sh, sm = sunrise:match("T(%d%d):(%d%d)")
	local eh, em = sunset:match("T(%d%d):(%d%d)")
	if not sh or not sm or not eh or not em then
		return nil
	end
	sh, sm, eh, em = tonumber(sh), tonumber(sm), tonumber(eh), tonumber(em)
	sm = round_down_quarter(sm)
	em = round_down_quarter(em)
	local sunrise_decimal = sh + sm / 60
	local sunset_decimal = eh + em / 60
	util.log(string.format("sunrise/sunset from Open-Meteo: %02d:%02d / %02d:%02d", sh, sm, eh, em), cfg)
	return sunrise_decimal, sunset_decimal
end

local function sun_times_sunwait(lat, lon, cfg, util)
	if not util.command_exists("sunwait") then
		return nil
	end
	local lat_dir = lat >= 0 and "N" or "S"
	local lon_dir = lon >= 0 and "E" or "W"
	local cmd = string.format("sunwait -p %0.4f%s %0.4f%s 2>/dev/null", math.abs(lat), lat_dir, math.abs(lon), lon_dir)
	local out = util.run_cmd(cmd)
	if not out then
		return nil
	end
	local sh, sm, eh, em = out:match("Sun rises%s+(%d%d)(%d%d).-[Ss]ets%s+(%d%d)(%d%d)")
	if not sh then
		return nil
	end
	sh, sm, eh, em = tonumber(sh), tonumber(sm), tonumber(eh), tonumber(em)
	sm = round_down_quarter(sm)
	em = round_down_quarter(em)
	local sunrise_decimal = sh + sm / 60
	local sunset_decimal = eh + em / 60
	util.log(string.format("sunrise/sunset from sunwait: %02d:%02d / %02d:%02d", sh, sm, eh, em), cfg)
	return sunrise_decimal, sunset_decimal
end

function Solar.get_location(cfg, state, util)
	if
		cfg.manual_lat
		and cfg.manual_lon
		and valid_coord(cfg.manual_lat, -90, 90)
		and valid_coord(cfg.manual_lon, -180, 180)
	then
		state.lat, state.lon = cfg.manual_lat, cfg.manual_lon
		util.log("Using manual coordinates: " .. cfg.manual_lat .. "," .. cfg.manual_lon, cfg)
		return true
	end

	if cfg.location_enabled then
		local lat, lon = ip_geolocate(util)
		if lat and lon then
			state.lat, state.lon = lat, lon
			util.log("Coordinates from IP: " .. lat .. "," .. lon, cfg)
			return true
		end
	end

	local lat, lon = timezone_fallback(util)
	state.lat, state.lon = lat, lon
	util.log("Timezone fallback coordinates: " .. lat .. "," .. lon, cfg)
	return cfg.location_enabled
end

function Solar.update_periods(cfg, state, util)
	if not cfg.location_enabled or not state.lat or not state.lon then
		return
	end

	local sunrise, sunset = sun_times_sunwait(state.lat, state.lon, cfg, util)
	if not sunrise then
		sunrise, sunset = sun_times_open_meteo(state.lat, state.lon, cfg, util)
	end

	if sunrise and sunset then
		state.sunrise = sunrise
		state.sunset = sunset
		cfg.start_hours.morning = math.max(0, sunrise - 0.25)
		cfg.start_hours.day = sunrise + 4
		cfg.start_hours.evening = math.max(0, sunset - 2.75)
		cfg.start_hours.night = math.min(23.75, sunset + 0.25)
		util.log(
			string.format(
				"Adjusted periods (h): morning=%.2f day=%.2f evening=%.2f night=%.2f",
				cfg.start_hours.morning,
				cfg.start_hours.day,
				cfg.start_hours.evening,
				cfg.start_hours.night
			),
			cfg
		)
	else
		util.log("Could not fetch sun times; using static start_hours", cfg)
		cfg.location_enabled = false
	end
end

return Solar
