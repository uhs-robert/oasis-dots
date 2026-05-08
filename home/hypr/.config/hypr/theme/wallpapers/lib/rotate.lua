-- hypr/.config/hypr/theme/wallpapers/lib/rotate.lua
-- Orchestrator: CLI parsing, config merge, locking, loop, hyprpaper start

local script_dir = (debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./")
local default_config = dofile(script_dir .. "../config.lua")

local Solar = require("wallpapers.lib.solar")
local Apply = require("wallpapers.lib.apply")

local unpack = table.unpack or unpack

local Rotate = {}

-- -------- utilities --------
local function log(msg, cfg)
	if cfg.verbose then
		io.stderr:write("[wallpaper] " .. msg .. "\n")
	end
end

local function deepcopy(tbl)
	if type(tbl) ~= "table" then
		return tbl
	end
	local out = {}
	for k, v in pairs(tbl) do
		out[k] = deepcopy(v)
	end
	return out
end

local function merge(base, override)
	local result = deepcopy(base)
	for k, v in pairs(override or {}) do
		if type(v) == "table" and type(result[k]) == "table" then
			result[k] = merge(result[k], v)
		else
			result[k] = v
		end
	end
	return result
end

local function run_cmd(cmd)
	local p = io.popen(cmd)
	if not p then
		return nil
	end
	local out = p:read("*all")
	p:close()
	if out == "" then
		return nil
	end
	return out
end

local function command_exists(cmd)
	local r = os.execute(string.format("command -v %s >/dev/null 2>&1", cmd))
	return r == true or r == 0
end

local function detect_signature()
	local sig = run_cmd("ls -1 /tmp/hypr 2>/dev/null | head -n 1")
	if sig then
		sig = sig:match("([^\n]+)")
	end
	return sig
end

local function sleep(seconds)
	os.execute(string.format("sleep %.3f", seconds))
end

-- -------- argument parsing --------
local function parse_args(argv)
	argv = argv or arg
	local overrides = {}
	local cli = { once = false }
	local i = 1
	while i <= #argv do
		local a = argv[i]
		if a == "--config" and argv[i + 1] then
			cli.config_path = argv[i + 1]
			i = i + 1
		elseif a == "--once" or a == "-o" then
			cli.once = true
		elseif a == "--verbose" or a == "-v" then
			overrides.verbose = true
		elseif (a == "--interval" or a == "-i") and argv[i + 1] then
			overrides.interval_minutes = tonumber(argv[i + 1])
			i = i + 1
		elseif a == "--dir" and argv[i + 1] then
			overrides.force_dir = argv[i + 1]
			i = i + 1
		elseif a == "--dir-morning" and argv[i + 1] then
			overrides.dirs = overrides.dirs or {}
			overrides.dirs.morning = argv[i + 1]
			i = i + 1
		elseif a == "--dir-day" and argv[i + 1] then
			overrides.dirs = overrides.dirs or {}
			overrides.dirs.day = argv[i + 1]
			i = i + 1
		elseif a == "--dir-evening" and argv[i + 1] then
			overrides.dirs = overrides.dirs or {}
			overrides.dirs.evening = argv[i + 1]
			i = i + 1
		elseif a == "--dir-night" and argv[i + 1] then
			overrides.dirs = overrides.dirs or {}
			overrides.dirs.night = argv[i + 1]
			i = i + 1
		elseif a == "--morning-hour" and argv[i + 1] then
			overrides.start_hours = overrides.start_hours or {}
			overrides.start_hours.morning = tonumber(argv[i + 1])
			i = i + 1
		elseif a == "--day-hour" and argv[i + 1] then
			overrides.start_hours = overrides.start_hours or {}
			overrides.start_hours.day = tonumber(argv[i + 1])
			i = i + 1
		elseif a == "--evening-hour" and argv[i + 1] then
			overrides.start_hours = overrides.start_hours or {}
			overrides.start_hours.evening = tonumber(argv[i + 1])
			i = i + 1
		elseif a == "--night-hour" and argv[i + 1] then
			overrides.start_hours = overrides.start_hours or {}
			overrides.start_hours.night = tonumber(argv[i + 1])
			i = i + 1
		elseif a == "--no-location" then
			overrides.location_enabled = false
		elseif a == "--latitude" and argv[i + 1] then
			overrides.manual_lat = tonumber(argv[i + 1])
			i = i + 1
		elseif a == "--longitude" and argv[i + 1] then
			overrides.manual_lon = tonumber(argv[i + 1])
			i = i + 1
		elseif a == "--coordinates" and argv[i + 1] then
			local lat, lon = argv[i + 1]:match("^(-?[%d%.]+),(-?[%d%.]+)$")
			overrides.manual_lat = lat and tonumber(lat) or overrides.manual_lat
			overrides.manual_lon = lon and tonumber(lon) or overrides.manual_lon
			i = i + 1
		elseif a == "--help" or a == "-h" then
			print([[
Options:
  --once, -o              Run one cycle and exit
  --verbose, -v           Verbose logging
  --config PATH           Use alternate config file
  --interval MIN          Minutes between rotations
  --dir PATH              Force one folder (disables time-of-day switching)
  --dir-morning PATH      Override morning folder
  --dir-day PATH          Override day folder
  --dir-evening PATH      Override evening folder
  --dir-night PATH        Override night folder
  --morning-hour H        Static start hour for morning
  --day-hour H            Static start hour for day
  --evening-hour H        Static start hour for evening
  --night-hour H          Static start hour for night
  --no-location           Disable location-based timing
  --latitude LAT          Manual latitude
  --longitude LON         Manual longitude
  --coordinates LAT,LON   Manual coordinates
]])
			return { help = true }, overrides
		end
		i = i + 1
	end
	return cli, overrides
end

-- -------- config load --------
local function load_config(opts, overrides)
	opts = opts or {}
	local default_path = script_dir .. "../config.lua"
	local cfg_path = opts.config_path or default_path

	local user_cfg = {}
	local ok, result = pcall(dofile, cfg_path)
	if ok and type(result) == "table" then
		user_cfg = result
	else
		io.stderr:write("Warning: could not load config at " .. cfg_path .. "; using defaults\n")
	end

	local cfg = merge(default_config, user_cfg)
	cfg = merge(cfg, overrides or {})
	cfg.interval_minutes = cfg.interval_minutes or 15
	cfg.interval_seconds = cfg.interval_minutes * 60
	return cfg
end

-- -------- locking --------
local function pid_alive(pid)
	if not pid then
		return false
	end
	local r = os.execute(string.format("kill -0 %s >/dev/null 2>&1", pid))
	return r == true or r == 0
end

local function acquire_lock(path)
	-- Lua 5.1 lacks "x" mode; do a simple existence check then create.
	local existing = io.open(path, "r")
	if existing then
		local pid = existing:read("*l")
		existing:close()
		if pid and pid_alive(pid) then
			return nil, "locked"
		else
			-- stale lock, try to overwrite
			os.remove(path)
		end
	end

	local f, err = io.open(path, "w")
	if not f then
		return nil, err or "locked"
	end
	f:write(tostring(os.getpid and os.getpid() or io.popen("echo $$"):read("*l")))
	f:close()
	local function cleanup()
		os.remove(path)
	end
	return cleanup
end

-- -------- hyprpaper --------
local function ensure_hyprpaper(cfg, util)
	if os.execute("pgrep -x hyprpaper >/dev/null 2>&1") ~= 0 then
		util.log("Starting hyprpaper...", cfg)
		local cmd = util.signature and string.format("HYPRLAND_INSTANCE_SIGNATURE=%s hyprpaper", util.signature)
			or "hyprpaper"
		os.execute(cmd .. " >/dev/null 2>&1 &")
		util.sleep(1)
	end
end

-- -------- run --------
function Rotate.start(opts)
	opts = opts or {}
	local cli, overrides = parse_args(opts.argv or arg)
	if cli.help then
		return true
	end

	local cfg = load_config({ config_path = cli.config_path }, overrides)

	local util = {
		log = log,
		run_cmd = run_cmd,
		command_exists = command_exists,
		sleep = sleep,
		signature = detect_signature(),
	}

	math.randomseed(os.time())

	local lock_path = opts.lock_path or "/tmp/hypr-wallpaper-day-system.lock"
	local cleanup_lock, lock_err = acquire_lock(lock_path)
	if not cleanup_lock then
		io.stderr:write("Another instance appears to be running (lock: " .. lock_path .. ")\n")
		return false, lock_err
	end

	if opts.start_hyprpaper ~= false then
		ensure_hyprpaper(cfg, util)
	end

	local state = {}
	local last_loc_refresh = os.time()

	-- Initialize solar calculations only if time-of-day is enabled
	if cfg.time_of_day_enabled then
		Solar.get_location(cfg, state, util)
		Solar.update_periods(cfg, state, util)
	end

	local function maybe_refresh()
		if not cfg.time_of_day_enabled or not cfg.location_enabled then
			return
		end
		local now = os.time()
		if now - last_loc_refresh >= cfg.refresh_interval_seconds then
			last_loc_refresh = now
			Solar.get_location(cfg, state, util)
			Solar.update_periods(cfg, state, util)
		end
	end

	local function cycle()
		maybe_refresh()
		local ok = Apply.to_monitors(cfg, util)
		if not ok then
			util.log("Wallpaper application failed; will retry.", cfg)
		end
	end

	-- Apply once and exit if rotation is disabled or --once flag is used
	if not cfg.rotation_enabled or opts.once or cli.once then
		cycle()
		cleanup_lock()
		return true
	end

	-- Rotation loop
	while true do
		cycle()
		util.sleep(cfg.interval_seconds)
	end
end

-- CLI entry
function Rotate.main_cli(argv)
	local ok = Rotate.start({ argv = argv })
	if not ok then
		os.exit(1)
	end
end

return Rotate
