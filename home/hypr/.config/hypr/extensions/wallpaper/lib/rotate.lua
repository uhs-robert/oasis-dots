-- home/hypr/.config/hypr/extensions/wallpaper/lib/rotate.lua
-- Orchestrator: CLI parsing, config merge, locking, loop, hyprpaper start

local script_dir = (debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./")
local default_config = dofile(script_dir .. "../config.lua")
local CUSTOM_DIR = script_dir .. "../../../custom/"

local Solar = require("wallpaper.lib.solar") ---@class Solar
local Apply = require("wallpaper.lib.apply") ---@class Apply
local Audit = require("wallpaper.lib.audit") ---@class Audit
local SettingsPage = require("wallpaper.lib.settings_page") ---@class SettingsPage

local POLL_SECONDS = 2

--- @class Rotate
--- @field start fun(opts?: { argv?: string[], lock_path?: string, once?: boolean, start_hyprpaper?: boolean }): boolean, string|nil Main entry point; parses args, loads config, runs one cycle or the rotation loop
--- @field init fun(argv?: string[]) CLI entry point; calls start() and exits 1 on failure
local Rotate = {}

--- Write `msg` to stderr when `cfg.verbose` is set.
--- @param msg string
--- @param cfg table wallpaper config
local function log(msg, cfg)
  if cfg.verbose then io.stderr:write("[wallpaper] " .. msg .. "\n") end
end

--- Recursively deep-copy a table (non-tables returned as-is).
--- @param tbl any
--- @return any
local function deepcopy(tbl)
  if type(tbl) ~= "table" then return tbl end
  local out = {}
  for k, v in pairs(tbl) do
    out[k] = deepcopy(v)
  end
  return out
end

--- Deep-merge `override` into a copy of `base`. Nested tables are merged
--- recursively; scalar values in `override` win.
--- @param base table
--- @param override table|nil
--- @return table merged result
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

--- Run a shell command and return its stdout, or nil if empty/failed.
--- @param cmd string
--- @return string|nil
local function run_cmd(cmd)
  local p = io.popen(cmd)
  if not p then return nil end
  local out = p:read("*all")
  p:close()
  if out == "" then return nil end
  return out
end

--- Return true if `cmd` is available on PATH.
--- @param cmd string
--- @return boolean
local function command_exists(cmd)
  local r = os.execute(string.format("command -v %s >/dev/null 2>&1", cmd))
  return r == true or r == 0
end

--- Sleep for `seconds` (fractional seconds supported).
--- @param seconds number
local function sleep(seconds) os.execute(string.format("sleep %.3f", seconds)) end

--- Parse `argv` into a CLI options table and a config-override table.
--- Returns `{ help = true }` as the first value when `--help` is passed.
--- @param argv string[]|nil defaults to the global `arg`
--- @return table cli, table overrides
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
    elseif a == "--audit" then
      cli.audit = true
    elseif a == "--monitor" and argv[i + 1] then
      overrides.target_monitor = argv[i + 1]
      i = i + 1
    elseif a == "--verbose" or a == "-v" then
      overrides.verbose = true
    elseif (a == "--interval" or a == "-i") and argv[i + 1] then
      overrides.interval_minutes = tonumber(argv[i + 1])
      i = i + 1
    elseif a == "--dir" and argv[i + 1] then
      overrides.force_dir = argv[i + 1]
      i = i + 1
    elseif a == "--season" and argv[i + 1] then
      overrides.force_season = argv[i + 1]
      i = i + 1
    elseif a == "--no-seasons" then
      overrides.seasons_enabled = false
    elseif a == "--weather" and argv[i + 1] then
      overrides.force_weather = argv[i + 1]
      i = i + 1
    elseif a == "--no-weather" then
      overrides.weather_enabled = false
    elseif a == "--dawn-hour" and argv[i + 1] then
      overrides.start_hours = overrides.start_hours or {}
      overrides.start_hours.dawn = tonumber(argv[i + 1])
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
    elseif a == "--location" then
      overrides.location_enabled = true
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
  --audit                 Check folder sizes, unused images and stray folders, then exit
  --monitor NAME          Apply to one specific monitor only (implies --once)
  --verbose, -v           Verbose logging
  --config PATH           Use alternate config file
  --interval MIN          Minutes between rotations
  --dir PATH              Force one folder (disables time-of-day switching)
  --season NAME           Force spring, summer, fall or winter
  --no-seasons            Ignore season folders
  --weather NAME          Force rain, snow or cloudy
  --no-weather            Ignore weather folders
  --dawn-hour H           Static start hour for dawn
  --day-hour H            Static start hour for day
  --evening-hour H        Static start hour for evening
  --night-hour H          Static start hour for night
  --no-location           Disable location-based timing
  --location              Follow the sun (Quickshell cache first, then online lookups)
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

--- Return true if `path` can be opened for reading.
--- @param path string
--- @return boolean
local function readable(path)
  local f = io.open(path, "r")
  if not f then return false end
  f:close()
  return true
end

--- Layer the Settings page values over `cfg`, skipping keys a CLI flag set.
--- A key the page no longer sets falls back to its value from the config files.
--- @param cfg table wallpaper config, changed in place; `cfg.file_settings` holds the config-file values
--- @param settings table result of `SettingsPage.settings`
--- @param overrides table CLI-derived overrides
local function apply_settings(cfg, settings, overrides)
  for _, key in ipairs(SettingsPage.SETTING_KEYS) do
    if overrides[key] == nil then
      if settings[key] ~= nil then
        cfg[key] = settings[key]
      else
        cfg[key] = cfg.file_settings[key]
      end
    end
  end
  cfg.interval_seconds = cfg.interval_minutes * 60
end

--- Load and merge configuration. Layers `default_config`, then the user file
--- (`--config PATH`, else `custom/wallpaper.lua` when present), then the Settings
--- page state, then `overrides`.
--- @param opts table|nil `{ config_path?: string }`
--- @param overrides table CLI-derived overrides to layer last
--- @param settings table result of `SettingsPage.settings`
--- @return table merged config
local function load_config(opts, overrides, settings)
  opts = opts or {}
  local cfg_path = opts.config_path
  if not cfg_path and readable(CUSTOM_DIR .. "wallpaper.lua") then cfg_path = CUSTOM_DIR .. "wallpaper.lua" end

  local user_cfg = {}
  if cfg_path then
    local ok, result = pcall(dofile, cfg_path)
    if ok and type(result) == "table" then
      user_cfg = result
    else
      io.stderr:write("Warning: could not load config at " .. cfg_path .. "; using defaults\n")
      if not ok then io.stderr:write(tostring(result) .. "\n") end
    end
  end

  local cfg = merge(default_config, user_cfg)
  cfg = merge(cfg, overrides)
  cfg.interval_minutes = cfg.interval_minutes or 15
  cfg.file_settings = {}
  for _, key in ipairs(SettingsPage.SETTING_KEYS) do
    cfg.file_settings[key] = cfg[key]
  end
  apply_settings(cfg, settings, overrides)
  return cfg
end

-- -------- locking --------

--- Return the PID of the current process via /proc/self/status.
--- @return string|nil
local function self_pid()
  local f = io.open("/proc/self/status", "r")
  if not f then return nil end
  local content = f:read("*all")
  f:close()
  return content:match("Pid:%s*(%d+)")
end

--- Return true if process `pid` is still alive (via `kill -0`).
--- @param pid string|nil
--- @return boolean
local function pid_alive(pid)
  if not pid then return false end
  local r = os.execute(string.format("kill -0 %s >/dev/null 2>&1", pid))
  return r == true or r == 0
end

--- Acquire a PID-based lock file at `path`.
--- Removes stale locks (dead PID). Returns true on success,
--- or `nil, reason` if another live instance holds the lock.
--- @param path string lock file path
--- @return true|nil ok, string|nil err
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
  if not f then return nil, err or "locked" end
  f:write(tostring(self_pid() or ""))
  f:close()
  return true
end

-- -------- history --------

local HISTORY_PATH = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/hypr-wallpaper-history"

--- Read the recently shown wallpaper paths, oldest first.
--- @return string[]
local function read_history()
  local history = {}
  local f = io.open(HISTORY_PATH, "r")
  if not f then return history end
  for line in f:lines() do
    if line ~= "" then table.insert(history, line) end
  end
  f:close()
  return history
end

--- Append `paths` to `history` and save its newest `size` entries.
--- @param history string[]
--- @param paths table<string, string> monitor name to wallpaper path
--- @param size integer
local function write_history(history, paths, size)
  for _, path in pairs(paths) do
    table.insert(history, path)
  end
  local f = io.open(HISTORY_PATH, "w")
  if not f then return end
  for i = math.max(1, #history - size + 1), #history do
    f:write(history[i], "\n")
  end
  f:close()
end

-- -------- hyprpaper --------

--- Start hyprpaper in the background if it is not already running, with `custom/hyprpaper.conf` when present.
--- @param cfg table wallpaper config (used for logging)
--- @param util table shared utility object
local function ensure_hyprpaper(cfg, util)
  local r = os.execute("pgrep -x hyprpaper >/dev/null 2>&1")
  if r ~= true and r ~= 0 then
    util.log("Starting hyprpaper...", cfg)
    local cmd = util.signature and string.format("HYPRLAND_INSTANCE_SIGNATURE=%s hyprpaper", util.signature)
      or "hyprpaper"
    local conf = CUSTOM_DIR .. "hyprpaper.conf"
    if readable(conf) then cmd = string.format("%s -c '%s'", cmd, conf) end
    os.execute(cmd .. " >/dev/null 2>&1 &")
    util.sleep(1)
  end
end

-- -------- run --------

--- Main entry point. Parses args, loads config, acquires lock if needed,
--- initialises solar state, then runs one cycle or the rotation loop.
--- @param opts table|nil `{ argv?, lock_path?, once?, start_hyprpaper? }`
--- @return boolean ok, string|nil err
function Rotate.start(opts)
  opts = opts or {}
  local cli, overrides = parse_args(opts.argv or arg)
  if cli.help then return true end

  local settings_raw, settings_state = SettingsPage.read()
  local cfg = load_config({ config_path = cli.config_path }, overrides, SettingsPage.settings(settings_state or {}))
  settings_state = settings_state or {}
  if cli.audit then
    Audit.run(cfg)
    return true
  end

  local util = {
    log = log,
    run_cmd = run_cmd,
    command_exists = command_exists,
    sleep = sleep,
    signature = Apply.detect_signature(),
  }

  math.randomseed(os.time())

  -- One-shot runs don't need the lock, only the rotation loop needs singleton enforcement.
  local one_shot = not cfg.rotation_enabled or opts.once or cli.once or (cfg.target_monitor ~= nil)
  if not one_shot then
    local lock_path = opts.lock_path or "/tmp/hypr-wallpaper-day-system.lock"
    local locked, lock_err = acquire_lock(lock_path)
    if not locked then
      io.stderr:write("Another instance appears to be running (lock: " .. lock_path .. ")\n")
      return false, lock_err
    end
  end

  if opts.start_hyprpaper ~= false then ensure_hyprpaper(cfg, util) end

  local state = {}
  local last_loc_refresh = os.time()

  local function refresh_solar()
    Solar.get_location(cfg, state, util)
    Solar.update_periods(cfg, state, util)
    cfg.southern_hemisphere = state.lat ~= nil and state.lat < 0
  end

  -- Initialize solar calculations only if time-of-day is enabled
  if cfg.time_of_day_enabled then refresh_solar() end

  local function maybe_refresh()
    if not cfg.time_of_day_enabled or not cfg.location_enabled then return end
    local now = os.time()
    if now - last_loc_refresh >= cfg.refresh_interval_seconds then
      last_loc_refresh = now
      refresh_solar()
    end
  end

  -- Authoritative monitor -> wallpaper-path map. Drives global de-dup: a partial
  -- (settle/hotplug) update reserves the paths already live on other monitors so
  -- no two monitors ever share a wallpaper.
  local APPLIED_WALLPAPERS = {}

  -- SettingsPage in effect at the last cycle, so a settings change can tell which monitors changed.
  local active_pins = {}

  local function covered_set()
    local set = {}
    for mon in pairs(APPLIED_WALLPAPERS) do
      set[mon] = true
    end
    return set
  end

  --- @param repicked table<string, boolean>|nil monitors about to get a new image; their current one is free
  local function reserved_set(repicked)
    local set = {}
    for mon, path in pairs(APPLIED_WALLPAPERS) do
      if not (repicked and repicked[mon]) then set[path] = true end
    end
    return set
  end

  local loop_pid = (not one_shot) and tonumber(self_pid()) or nil
  -- The status text this process last wrote; any other text means a one-shot run changed wallpapers.
  local own_status_text

  --- Write the status file: what is live on each connected monitor, merged over the previous
  --- status so a one-shot run keeps the entries it did not touch.
  --- @param applied table<string, string> monitor name to path set by the cycle that just ran
  local function publish_status(applied)
    local previous = SettingsPage.read_status()
    local previous_monitors = type(previous.monitors) == "table" and previous.monitors or {}
    local pid = loop_pid or previous.pid
    local monitors_status = {}
    for _, mon in ipairs(Apply.list_monitors(cfg, util)) do
      local path = applied[mon.name] or (previous_monitors[mon.name] or {}).path
      if path then
        monitors_status[mon.name] =
          { description = mon.description, path = path, pinned = active_pins[mon.description] ~= nil }
      end
    end
    own_status_text = SettingsPage.write_status({
      collection = cfg.wallpaper_dir,
      running = loop_pid ~= nil or (pid ~= nil and pid_alive(tostring(pid))),
      pid = pid,
      settings = {
        rotation = cfg.rotation,
        interval_minutes = cfg.interval_minutes,
        time_of_day_enabled = cfg.time_of_day_enabled,
        seasons_enabled = cfg.seasons_enabled,
        weather_enabled = cfg.weather_enabled,
      },
      monitors = monitors_status,
      updated = os.time(),
    })
  end

  --- Apply wallpapers and record the result.
  --- @param mode "full"|"settle"|"partial" full re-randomizes every monitor (distinct set);
  --- settle only fills monitors not yet in `APPLIED_WALLPAPERS`, avoiding live wallpapers;
  --- partial re-picks only the monitors in `only` (or the `--monitor` target), avoiding live wallpapers.
  --- @param only table<string, boolean>|nil monitors a partial cycle re-picks
  local function cycle(mode, only)
    maybe_refresh()
    active_pins = SettingsPage.usable(settings_state, cfg, util)
    local history = cfg.history_size > 0 and read_history() or {}
    local cycle_opts = { history = history, pins = active_pins }
    if mode == "settle" then
      cycle_opts.exclude = covered_set()
      cycle_opts.reserved = reserved_set()
    elseif mode == "partial" then
      cycle_opts.only = only
      cycle_opts.reserved = reserved_set(only or (cfg.target_monitor and { [cfg.target_monitor] = true }))
    end
    local ok, applied, pinned = Apply.to_monitors(cfg, util, cycle_opts)
    if not ok then util.log("Wallpaper application failed; will retry.", cfg) end
    if cfg.history_size > 0 then
      local shown = {}
      for mon, path in pairs(applied) do
        if not pinned[mon] then shown[mon] = path end
      end
      write_history(history, shown, cfg.history_size)
    end
    if mode == "full" then
      APPLIED_WALLPAPERS = applied -- full refresh replaces the map
    else
      for mon, path in pairs(applied) do
        APPLIED_WALLPAPERS[mon] = path
      end
    end
    publish_status(applied)
    return ok
  end

  if one_shot then
    if cfg.target_monitor then
      -- A lone monitor must not copy what the others show.
      for mon, entry in pairs(SettingsPage.read_status().monitors or {}) do
        if type(entry) == "table" and entry.path then APPLIED_WALLPAPERS[mon] = entry.path end
      end
      cycle("partial")
    else
      cycle("full")
    end
    return true
  end

  -- Startup: retry with short delays if hyprpaper isn't ready yet
  if not cycle("full") then
    local startup_retries = 5
    local startup_delay_s = 3
    for i = 1, startup_retries do
      util.log(string.format("Startup retry %d/%d in %ds...", i, startup_retries, startup_delay_s), cfg)
      util.sleep(startup_delay_s)
      if cycle("full") then break end
    end
  end

  -- Settle: catch monitors that come up a beat late. Each pass only fills the
  -- still-uncovered monitors and reserves the wallpapers already on the others.
  local settle_cycles = 5
  local settle_delay_s = 3
  for _ = 1, settle_cycles do
    util.sleep(settle_delay_s)
    cycle("settle")
  end

  local due
  local function schedule()
    due = os.time() + math.max(1, math.min(cfg.interval_seconds, Apply.seconds_to_period_change(cfg)))
  end
  schedule()

  --- React to a changed settings file: new pins show at once, released monitors get a fresh
  --- pick, and a changed pool or schedule setting adjusts the rotation.
  local function apply_settings_change()
    local raw, decoded = SettingsPage.read()
    if raw == settings_raw then return end
    settings_raw = raw
    if not decoded then
      util.log("wallpaper.json is not valid JSON; keeping the previous settings", cfg)
      return
    end
    local before = {
      rotation = cfg.rotation,
      interval_minutes = cfg.interval_minutes,
      time_of_day_enabled = cfg.time_of_day_enabled,
      seasons_enabled = cfg.seasons_enabled,
      weather_enabled = cfg.weather_enabled,
    }
    local before_pins = active_pins
    settings_state = decoded
    apply_settings(cfg, SettingsPage.settings(decoded), overrides)
    util.log("wallpaper.json changed; settings reloaded", cfg)

    local pool_changed = before.time_of_day_enabled ~= cfg.time_of_day_enabled
      or before.seasons_enabled ~= cfg.seasons_enabled
      or before.weather_enabled ~= cfg.weather_enabled
    if cfg.time_of_day_enabled and not before.time_of_day_enabled then refresh_solar() end

    if pool_changed and cfg.rotation then
      cycle("full")
      schedule()
      return
    end

    local new_pins = SettingsPage.usable(decoded, cfg, util)
    local changed = {}
    for _, mon in ipairs(Apply.list_monitors(cfg, util)) do
      if new_pins[mon.description] ~= before_pins[mon.description] then changed[mon.name] = true end
    end
    if next(changed) then cycle("partial", changed) end
    if before.rotation ~= cfg.rotation or before.interval_minutes ~= cfg.interval_minutes then schedule() end
    if not next(changed) then
      active_pins = new_pins
      publish_status({})
    end
  end

  --- Take over what a one-shot run (`--once` from Settings or SUPER+Q W, or a hotplug `--monitor`)
  --- applied, so later picks avoid those images and a manual rotation restarts the interval.
  local function adopt_outside_changes()
    local text = SettingsPage.read_status_text()
    if not text or text == own_status_text then return end
    own_status_text = text
    local monitors_status = SettingsPage.read_status().monitors
    if type(monitors_status) ~= "table" then return end
    APPLIED_WALLPAPERS = {}
    for mon, entry in pairs(monitors_status) do
      if type(entry) == "table" and type(entry.path) == "string" then APPLIED_WALLPAPERS[mon] = entry.path end
    end
    schedule()
  end

  -- Rotation loop (startup already did the first cycle). Wakes early for a
  -- period change so the new period's wallpapers show on time, and polls the
  -- settings file in short slices since there is no file watcher.
  while true do
    util.sleep(POLL_SECONDS)
    adopt_outside_changes()
    apply_settings_change()
    if cfg.rotation and os.time() >= due then
      cycle("full")
      schedule()
    end
  end
end

--- CLI entry point. Calls `Rotate.start` and exits 1 on failure.
--- @param argv string[]|nil
function Rotate.init(argv)
  local ok = Rotate.start({ argv = argv })
  if not ok then os.exit(1) end
end

return Rotate
