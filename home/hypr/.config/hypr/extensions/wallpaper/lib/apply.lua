-- home/hypr/.config/hypr/extensions/wallpaper/lib/apply.lua
-- Period resolution, file selection, and hyprpaper application

--- @class Apply
--- @field to_monitors fun(cfg: table, util: table, opts?: { exclude?: table<string, boolean>, reserved?: table<string, boolean>, history?: string[] }): boolean, table<string, string> Apply wallpapers to all active monitors (or cfg.target_monitor if set); returns ok plus a map of monitor name to the wallpaper path applied
--- @field detect_signature fun(skip_env?: boolean): string|nil Current Hyprland instance signature from the environment or the runtime dir
--- @field list_images fun(dir: string, skip?: string[]): string[] Public wrapper around list_images for external callers
--- @field folder fun(name: string): string Folder name for a period, season or weather key
--- @field PERIODS string[] Period keys in day order
--- @field SEASONS string[] Season keys, without `any`
--- @field WEATHERS string[] Weather keys
--- @field seconds_to_period_change fun(cfg: table): number Seconds until the next time-of-day period starts
local Apply = {}

local PERIODS = { "dawn", "day", "evening", "night" }
local SEASONS = { "spring", "summer", "fall", "winter" }
local WEATHERS = { "rain", "snow", "cloudy" }
local ANY = "any"

--- @param name string key such as `dawn` or `fall`
--- @return string folder name such as `Dawn` or `Fall`
local function folder(name) return (name:gsub("^%l", string.upper)) end

--- Find all image files under `dir` (recursive), resolved to their real paths.
--- @param dir string absolute path to search
--- @param skip string[]|nil subfolder names not descended into
--- @return string[] list of distinct absolute file paths
local function list_images(dir, skip)
  local prune = ""
  if skip and #skip > 0 then
    local names = {}
    for _, name in ipairs(skip) do
      table.insert(names, string.format('-name "%s"', name))
    end
    prune = "-mindepth 1 -type d \\( " .. table.concat(names, " -o ") .. " \\) -prune -o "
  end
  -- NUL-separated to safely handle spaces/newlines
  local cmd = string.format(
    'find -L "%s" %s-type f \\( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.webp" -o -iname "*.bmp" \\) -exec realpath -z {} + 2>/dev/null',
    dir,
    prune
  )
  local p = io.popen(cmd)
  if not p then return {} end
  local data = p:read("*a") or ""
  p:close()
  local files, seen = {}, {}
  for entry in data:gmatch("([^%z]+)") do
    if not seen[entry] then
      seen[entry] = true
      table.insert(files, entry)
    end
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

--- Return the entries of `list` that are not keys of `blocked`.
--- @param list string[]
--- @param blocked table<string, boolean>
--- @return string[]
local function unblocked(list, blocked)
  local out = {}
  for _, f in ipairs(list) do
    if not blocked[f] then table.insert(out, f) end
  end
  return out
end

--- Drop reserved and recently shown paths while `count` picks still remain.
--- The oldest history entries are forgiven first, then the reservations.
--- History never blocks `favored`: weather folders are small and must keep showing.
--- @param files string[]
--- @param favored string[]
--- @param count integer
--- @param reserved table<string, boolean>
--- @param history string[] recently shown paths, oldest first
--- @return string[] files, string[] favored
local function narrow(files, favored, count, reserved, history)
  local free_favored = unblocked(favored, reserved)
  for first = 1, #history + 1 do
    local blocked = {}
    for path in pairs(reserved) do
      blocked[path] = true
    end
    for i = first, #history do
      blocked[history[i]] = true
    end
    local free_files = unblocked(files, blocked)
    if #free_files + #free_favored >= count then return free_files, free_favored end
  end
  return files, favored
end

--- Pick `count` wallpapers, cycling if fewer files exist. Each pick comes from
--- `opts.favored` with probability `opts.chance`, else from `files`.
--- @param files string[] pool to pick from
--- @param count integer number of wallpapers needed
--- @param opts { reserved?: table<string, boolean>, history?: string[], favored?: string[], chance?: number }
--- @return string[] selected file paths (empty if both pools are)
local function pick_wallpapers(files, count, opts)
  local favored = opts.favored or {}
  if #files + #favored == 0 then return {} end
  files, favored = narrow(files, favored, count, opts.reserved or {}, opts.history or {})
  shuffle(files)
  shuffle(favored)
  local total = #files + #favored
  local out, used_files, used_favored = {}, 0, 0
  for i = 1, count do
    if used_favored < #favored and (used_files >= #files or math.random() < (opts.chance or 0)) then
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
--- @param cfg table wallpaper config with `start_hours.{dawn,day,evening,night}`
--- @return "dawn"|"day"|"evening"|"night"
local function current_period(cfg)
  local t = os.date("*t")
  local ct = t.hour + t.min / 60 + t.sec / 3600
  local m = cfg.start_hours.dawn
  local d = cfg.start_hours.day
  local e = cfg.start_hours.evening
  local n = cfg.start_hours.night

  if ct >= n or ct < m then
    return "night"
  elseif ct >= m and ct < d then
    return "dawn"
  elseif ct >= d and ct < e then
    return "day"
  else
    return "evening"
  end
end

local OPPOSITE_SEASON = { spring = "fall", summer = "winter", fall = "spring", winter = "summer" }

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

--- Map a WMO weather code to a weather key, or nil for clear or partly cloudy skies.
--- @param code integer
--- @return "rain"|"snow"|"cloudy"|nil
local function weather_kind(code)
  if code >= 95 or (code >= 51 and code <= 67) or (code >= 80 and code <= 82) then return "rain" end
  if (code >= 71 and code <= 77) or code == 85 or code == 86 then return "snow" end
  if code == 3 or code == 45 or code == 48 then return "cloudy" end
  return nil
end

--- Return the current weather key from the Quickshell weather cache, or nil when off, clear or stale.
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

--- Build the pool from `Any/<Period>` and `<Season>/<Period>`. Their weather subfolders are
--- skipped, except the current weather's, which is returned separately as the favored pool.
--- @param cfg table wallpaper config
--- @param period string period key
--- @param season string|nil season key
--- @param weather string|nil weather key
--- @return string[] files, string[] dirs the pool was read from, string[] favored weather files
local function resolve_pool(cfg, period, season, weather)
  if cfg.force_dir then return list_images(cfg.force_dir), { cfg.force_dir }, {} end
  local skip = {}
  for _, name in ipairs(WEATHERS) do
    table.insert(skip, folder(name))
  end

  local period_dirs = { cfg.wallpaper_dir .. "/" .. folder(ANY) .. "/" .. folder(period) }
  if season then table.insert(period_dirs, cfg.wallpaper_dir .. "/" .. folder(season) .. "/" .. folder(period)) end

  local seen = {}
  local function add(list, dirs, dir, found)
    local before = #list
    for _, f in ipairs(found) do
      if not seen[f] then
        seen[f] = true
        table.insert(list, f)
      end
    end
    if #list > before then table.insert(dirs, dir) end
  end

  local favored, favored_dirs = {}, {}
  if weather then
    for _, dir in ipairs(period_dirs) do
      local nested = dir .. "/" .. folder(weather)
      add(favored, favored_dirs, nested, list_images(nested))
    end
  end

  local files, dirs = {}, {}
  for _, dir in ipairs(period_dirs) do
    add(files, dirs, dir, list_images(dir, skip))
  end
  if #files + #favored == 0 then add(files, dirs, cfg.wallpaper_dir, list_images(cfg.wallpaper_dir)) end
  for _, dir in ipairs(favored_dirs) do
    table.insert(dirs, dir)
  end
  return files, dirs, favored
end

--- Return the current period, season and weather; season and weather are nil when off.
--- @param cfg table wallpaper config
--- @return string period, string|nil season, string|nil weather
local function context(cfg)
  if not cfg.time_of_day_enabled then return "default", nil, nil end
  return current_period(cfg), current_season(cfg), current_weather(cfg)
end

--- @param period string
--- @param season string|nil
--- @param weather string|nil
--- @return string
local function label_of(period, season, weather)
  local label = season and (season .. " " .. period) or period
  if weather then label = label .. " " .. weather end
  return label
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

--- Return HYPRLAND_INSTANCE_SIGNATURE from the environment, else the newest instance in $XDG_RUNTIME_DIR/hypr, or nil.
--- @return string|nil
--- @param skip_env? boolean ignore HYPRLAND_INSTANCE_SIGNATURE, e.g. after it failed
function Apply.detect_signature(skip_env)
  local env_sig = not skip_env and os.getenv("HYPRLAND_INSTANCE_SIGNATURE")
  if env_sig and env_sig ~= "" then return env_sig end
  local runtime = os.getenv("XDG_RUNTIME_DIR")
  if not runtime or runtime == "" then return nil end
  local p = io.popen(string.format("ls -1t '%s/hypr' 2>/dev/null | head -n 1", runtime))
  if not p then return nil end
  local sig = p:read("*l")
  p:close()
  return (sig and sig ~= "") and sig or nil
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

  -- Try to auto-detect a signature
  local sig = Apply.detect_signature(true)

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
--- picks one image per monitor, then sets each via hyprpaper.
--- @param cfg table wallpaper config
--- @param util table shared utility object
--- @param opts table|nil `{ exclude?, reserved?, history? }`; monitors in `exclude` are skipped (startup settle); paths in `reserved` (live on other monitors) and `history` (recently shown, oldest first) are avoided when picking
--- @return boolean ok true on success, false if nothing could be applied
--- @return table<string, string> applied map of monitor name to the wallpaper path set this call
function Apply.to_monitors(cfg, util, opts)
  local period, season, weather = context(cfg)
  local files, dirs
  local favored = {}

  if cfg.time_of_day_enabled then
    files, dirs, favored = resolve_pool(cfg, period, season, weather)
  else
    local dir = cfg.force_dir or cfg.wallpaper_dir
    files, dirs = dir and list_images(dir) or {}, { dir }
  end

  local label = label_of(period, season, weather)
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

  local picks = pick_wallpapers(files, #mons, {
    reserved = opts and opts.reserved,
    history = opts and opts.history,
    favored = favored,
    chance = cfg.weather_chance,
  })

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
--- @param skip string[]|nil subfolder names not descended into
--- @return string[] image file paths
function Apply.list_images(dir, skip) return list_images(dir, skip) end

Apply.folder = folder
Apply.PERIODS = PERIODS
Apply.SEASONS = SEASONS
Apply.WEATHERS = WEATHERS

--- Seconds until the next time-of-day period starts; `math.huge` when periods are off.
--- @param cfg table wallpaper config
--- @return number
function Apply.seconds_to_period_change(cfg)
  if not cfg.time_of_day_enabled then return math.huge end
  local t = os.date("*t")
  local now_h = t.hour + t.min / 60 + t.sec / 3600
  local nearest = 24
  for _, start in pairs(cfg.start_hours) do
    local ahead = (start - now_h) % 24
    if ahead > 0 and ahead < nearest then nearest = ahead end
  end
  return nearest * 3600 + 1
end

return Apply
