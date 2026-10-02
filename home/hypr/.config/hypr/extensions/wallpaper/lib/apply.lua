-- home/hypr/.config/hypr/extensions/wallpaper/lib/apply.lua
-- Period resolution, file selection, and hyprpaper application

--- @class Apply
--- @field to_monitors fun(cfg: table, util: table, opts?: { exclude?: table<string, boolean>, reserved?: table<string, boolean> }): boolean, table<string, string> Apply wallpapers to all active monitors (or cfg.target_monitor if set); returns ok plus a map of monitor name to the wallpaper path applied
--- @field list_images fun(dir: string): string[] Public wrapper around list_images for external callers
local Apply = {}

--- Find all image files under `dir` (recursive, follows symlinks).
--- @param dir string absolute path to search
--- @return string[] list of absolute file paths
local function list_images(dir)
  -- Use -print0 to safely handle spaces/newlines
  local cmd = string.format(
    'find -L "%s" -type f \\( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.webp" -o -iname "*.bmp" \\) -print0 2>/dev/null',
    dir
  )
  local p = io.popen(cmd)
  if not p then return {} end
  local data = p:read("*a") or ""
  p:close()
  local files = {}
  for entry in data:gmatch("([^%z]+)") do
    table.insert(files, entry)
  end
  return files
end

--- In place shuffle.
--- @param t any[]
local function shuffle(t)
  for i = #t, 2, -1 do
    local j = math.random(i)
    t[i], t[j] = t[j], t[i]
  end
end

--- Pick `count` wallpapers, cycling if fewer files exist. Each pick comes from
--- `favored` with probability `chance`, else from `files`.
--- Paths in `reserved` (already live on other monitors) are avoided as long as
--- enough distinct files remain; otherwise the full pool is used as a fallback.
--- @param files string[] pool to pick from
--- @param count integer number of wallpapers needed
--- @param reserved table<string, boolean>|nil paths to avoid reusing
--- @param favored string[]|nil pool picked ahead of `files`
--- @param chance number|nil odds in [0, 1] that a pick comes from `favored`
--- @return string[] selected file paths (empty if both pools are)
local function pick_wallpapers(files, count, reserved, favored, chance)
  favored = favored or {}
  if #files + #favored == 0 then return {} end
  if reserved then
    local function unreserved(list)
      local avail = {}
      for _, f in ipairs(list) do
        if not reserved[f] then table.insert(avail, f) end
      end
      return avail
    end
    local free_files, free_favored = unreserved(files), unreserved(favored)
    -- Only honor reservations if the remaining pool can still fill every monitor.
    if #free_files + #free_favored >= count then
      files, favored = free_files, free_favored
    end
  end
  shuffle(files)
  shuffle(favored)
  local total = #files + #favored
  local out, used_files, used_favored = {}, 0, 0
  for i = 1, count do
    if used_favored < #favored and (used_files >= #files or math.random() < (chance or 0)) then
      used_favored = used_favored + 1
      out[i] = favored[used_favored]
    elseif used_files < #files then
      used_files = used_files + 1
      out[i] = files[used_files]
    else
      out[i] = out[((i - 1) % total) + 1]
    end
  end
  return out
end

--- Return the time-of-day period name based on `cfg.start_hours`.
--- @param cfg table wallpaper config with `start_hours.{morning,day,evening,night}`
--- @return "morning"|"day"|"evening"|"night"
local function current_period(cfg)
  local t = os.date("*t")
  local ct = t.hour + t.min / 60
  local m = cfg.start_hours.morning
  local d = cfg.start_hours.day
  local e = cfg.start_hours.evening
  local n = cfg.start_hours.night

  if ct >= n or ct < m then
    return "night"
  elseif ct >= m and ct < d then
    return "morning"
  elseif ct >= d and ct < e then
    return "day"
  else
    return "evening"
  end
end

local OPPOSITE_SEASON = { spring = "autumn", summer = "winter", autumn = "spring", winter = "summer" }

--- Return the current season from `cfg.season_start_months`, or nil when seasons are off.
--- @param cfg table wallpaper config
--- @return string|nil
local function current_season(cfg)
  if not cfg.seasons_enabled then return nil end
  if cfg.force_season then return cfg.force_season end
  local month = os.date("*t").month
  local season, season_start, latest, latest_start
  for name, start in pairs(cfg.season_start_months) do
    if start <= month and (not season_start or start > season_start) then
      season, season_start = name, start
    end
    if not latest_start or start > latest_start then
      latest, latest_start = name, start
    end
  end
  season = season or latest
  if cfg.southern_hemisphere then season = OPPOSITE_SEASON[season] or season end
  return season
end

--- Map a WMO weather code to a `cfg.weather_dirs` key, or nil for dry weather.
--- @param code integer
--- @return string|nil
local function weather_kind(code)
  if code >= 95 then return "storm" end
  if (code >= 71 and code <= 77) or code == 85 or code == 86 then return "snow" end
  if (code >= 51 and code <= 67) or (code >= 80 and code <= 82) then return "rain" end
  return nil
end

--- Return the current weather kind from the Quickshell weather cache, or nil when off, dry or stale.
--- @param cfg table wallpaper config
--- @return string|nil
local function current_weather(cfg)
  if not cfg.weather_enabled then return nil end
  if cfg.force_weather then return cfg.force_weather end
  local f = io.open(cfg.weather_cache or "", "r")
  if not f then return nil end
  local json = f:read("*a") or ""
  f:close()
  local code = tonumber(json:match('"current"%s*:%s*{[^}]-"code"%s*:%s*(%d+)'))
  local updated_ms = tonumber(json:match('"updated"%s*:%s*(%d+)'))
  if not code or not updated_ms then return nil end
  if os.time() - updated_ms / 1000 > cfg.weather_max_age_minutes * 60 then return nil end
  return weather_kind(code)
end

--- Build the pool for `period`: the period dir plus the current season's dir for that period.
--- `cfg.force_dir` replaces both; `cfg.default_wallpaper_dir` is used when both are empty.
--- @param cfg table wallpaper config
--- @param period string period name key into `cfg.dirs`
--- @param season string|nil season name key into `cfg.season_dirs`
--- @param weather string|nil weather name key into `cfg.weather_dirs`
--- @return string[] files, string[] dirs the pool was read from, string[] favored weather files
local function resolve_pool(cfg, period, season, weather)
  if cfg.force_dir then return list_images(cfg.force_dir), { cfg.force_dir }, {} end
  local season_dirs = season and cfg.season_dirs and cfg.season_dirs[season]
  local candidates = { cfg.dirs[period] }
  if season_dirs then table.insert(candidates, season_dirs[period]) end
  local files, dirs = {}, {}
  for _, dir in ipairs(candidates) do
    local found = list_images(dir)
    if #found > 0 then
      table.insert(dirs, dir)
      for _, f in ipairs(found) do
        table.insert(files, f)
      end
    end
  end
  if #files == 0 and cfg.default_wallpaper_dir then
    files, dirs = list_images(cfg.default_wallpaper_dir), { cfg.default_wallpaper_dir }
  end
  local weather_dir = weather and cfg.weather_dirs and cfg.weather_dirs[weather]
  local favored = weather_dir and list_images(weather_dir) or {}
  if #favored > 0 then table.insert(dirs, weather_dir) end
  return files, dirs, favored
end

--- Parse `hyprctl -j monitors` JSON output and return unique monitor names.
--- Only names containing a dash (and not purely numeric) are kept.
--- @param out string|nil raw JSON string
--- @return string[] monitor names
local function parse_monitors_json(out)
  local mons = {}
  if not out then return mons end
  -- Iterate monitor objects; keep only plausible monitor names (contain a dash, not just digits)
  for block in out:gmatch("{(.-)}") do
    local name = block:match('"name"%s*:%s*"([^"]+)"')
    if name and name:find("%-") and not name:match("^%d+$") then mons[name] = true end
  end
  local uniq = {}
  for name, _ in pairs(mons) do
    table.insert(uniq, name)
  end
  return uniq
end

--- Run a hyprctl command, retrying with an auto-detected HYPRLAND_INSTANCE_SIGNATURE if needed.
--- @param cmd string hyprctl subcommand and arguments
--- @param util table shared utility object with `run_cmd`, `log`, and optional `signature`
--- @return string|nil command output
local function hyprctl(cmd, util)
  -- Try with current env
  local base = util.signature and ("HYPRLAND_INSTANCE_SIGNATURE=" .. util.signature .. " ") or ""
  local out = util.run_cmd(base .. "hyprctl " .. cmd .. " 2>/dev/null")
  if out and out:match("%S") and not out:match("socket timeout") then return out end

  -- Try to auto-detect a signature from /tmp/hypr/*
  local sig = util.run_cmd("ls -1 /tmp/hypr 2>/dev/null | head -n 1")
  if sig then sig = sig:match("([^\n]+)") end

  if sig and sig ~= "" then
    local env_cmd = string.format("HYPRLAND_INSTANCE_SIGNATURE=%s hyprctl %s 2>/dev/null", sig, cmd)
    out = util.run_cmd(env_cmd)
    if out and out:match("%S") and not out:match("socket timeout") then
      util.log("hyprctl succeeded after setting HYPRLAND_INSTANCE_SIGNATURE=" .. sig, { verbose = true })
      return out
    end
  end

  return out
end

--- Return the list of active monitor names via hyprctl.
--- Tries JSON output first, falls back to text parsing.
--- @param cfg table wallpaper config (used for logging)
--- @param util table shared utility object
--- @return string[] monitor names
local function monitors(cfg, util)
  -- Prefer JSON output for reliability
  local out_json = hyprctl("-j monitors", util)
  local mons = parse_monitors_json(out_json)

  if #mons == 0 then
    -- Fallback to text parsing
    local out_txt = hyprctl("monitors | awk '/Monitor/ {print $2}'", util)
    local set = {}
    if out_txt then
      for m in out_txt:gmatch("[^\\n]+") do
        if m:find("%-") and not m:match("^%d+$") then set[m] = true end
      end
    end
    for name, _ in pairs(set) do
      table.insert(mons, name)
    end

    if #mons == 0 and (out_json or out_txt) then
      local raw = (out_json or "") .. (out_txt or "")
      util.log("hyprctl output (monitors) empty or unparsable:\n" .. raw, cfg)
      return {}
    end
  end

  return mons
end

--- Apply wallpapers to all active monitors (or `cfg.target_monitor` if set).
--- Resolves the pool from the current time-of-day period, season and weather,
--- picks one image per monitor, preloads via hyprpaper, then sets each.
--- @param cfg table wallpaper config
--- @param util table shared utility object
--- @param opts table|nil `{ exclude?, reserved? }`; monitors in `exclude` are skipped (startup settle, avoids re-randomizing covered monitors); paths in `reserved` are avoided when picking (keeps live wallpapers off other monitors)
--- @return boolean ok true on success, false if nothing could be applied
--- @return table<string, string> applied map of monitor name to the wallpaper path set this call
function Apply.to_monitors(cfg, util, opts)
  local period, season, weather, files, dirs
  local favored = {}

  -- Use time-of-day periods only if enabled
  if cfg.time_of_day_enabled then
    period = current_period(cfg)
    season = current_season(cfg)
    weather = current_weather(cfg)
    files, dirs, favored = resolve_pool(cfg, period, season, weather)
  else
    -- Skip time-of-day logic, use default directory directly
    period = "default"
    local dir = cfg.force_dir or cfg.default_wallpaper_dir
    files, dirs = dir and list_images(dir) or {}, { dir }
  end

  local label = season and (season .. " " .. period) or period
  if weather then label = label .. " " .. weather end
  local dir_list = table.concat(dirs, ", ")
  if #files + #favored == 0 then
    util.log("No wallpapers found in " .. dir_list .. " (period " .. label .. ")", cfg)
    return false, {}
  end

  local mons = monitors(cfg, util)
  if #mons == 0 then
    util.log("No monitors found via hyprctl monitors", cfg)
    return false, {}
  end

  if cfg.target_monitor then
    local found = false
    for _, name in ipairs(mons) do
      if name == cfg.target_monitor then
        found = true
        break
      end
    end
    if not found then
      util.log("Target monitor " .. cfg.target_monitor .. " not in active monitor list; skipping", cfg)
      return true, {}
    end

    -- Always (re)apply the current period to this monitor.
    mons = { cfg.target_monitor }
  end

  -- Drop already-covered monitors (startup settle re-runs to catch late monitors
  -- without re-randomizing the ones already set).
  if opts and opts.exclude then
    local filtered = {}
    for _, name in ipairs(mons) do
      if not opts.exclude[name] then table.insert(filtered, name) end
    end
    mons = filtered
    if #mons == 0 then return true, {} end
  end

  local picks = pick_wallpapers(files, #mons, opts and opts.reserved or nil, favored, cfg.weather_chance)

  util.log(
    string.format("Period %s -> %s; monitors=%d; pool=%d; weather=%d", label, dir_list, #mons, #files, #favored),
    cfg
  )
  if cfg.verbose then
    for i, img in ipairs(picks) do
      util.log(string.format("  pick[%d]=%s", i, img), cfg)
    end
  end

  local applied = {}
  for i, mon in ipairs(mons) do
    local img = picks[i]
    if img then
      img = img:gsub("[\r\n]", "")
      local f = io.open(img, "r")
      if not f then
        util.log(string.format("Skipping missing file: %s", img), cfg)
      else
        f:close()
        local base = util.signature and ("HYPRLAND_INSTANCE_SIGNATURE=" .. util.signature .. " ") or ""
        os.execute(string.format("%shyprctl hyprpaper preload '%s' >/dev/null 2>&1", base, img))
        local rc = os.execute(string.format("%shyprctl hyprpaper wallpaper '%s, %s' >/dev/null 2>&1", base, mon, img))
        if rc ~= 0 and rc ~= true then
          util.log(string.format("hyprpaper wallpaper failed (rc=%s) for %s on %s", tostring(rc), img, mon), cfg)
        else
          applied[mon] = img
        end
      end
    end
  end
  return true, applied
end

--- Public wrapper around `list_images` for external callers.
--- @param dir string directory to scan
--- @return string[] image file paths
function Apply.list_images(dir) return list_images(dir) end

return Apply
