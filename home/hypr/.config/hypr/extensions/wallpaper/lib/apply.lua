-- home/hypr/.config/hypr/extensions/wallpaper/lib/apply.lua
-- Period resolution, file selection, and hyprpaper application

--- @class Apply
--- @field to_monitors fun(cfg: table, util: table, opts?: { exclude?: table<string, boolean>, only?: table<string, boolean>, reserved?: table<string, boolean>, history?: string[], pins?: table<string, string> }): boolean, table<string, string>, table<string, boolean> Apply wallpapers to all active monitors (or cfg.target_monitor if set); returns ok, a map of monitor name to the wallpaper path applied, and the set of monitors that got a pin
--- @field list_monitors fun(cfg: table, util: table): { name: string, description: string }[] Active monitors; description is empty when only the text fallback worked
--- @field detect_signature fun(skip_env?: boolean): string|nil Current Hyprland instance signature from the environment or the runtime dir
--- @field list_images fun(dir: string, skip?: string[]): string[] Public wrapper around list_images for external callers
--- @field folder fun(name: string): string Folder name for a period, season or weather key
--- @field PERIODS string[] Period keys in day order
--- @field SEASONS string[] Season keys, without `any`
--- @field WEATHERS string[] Weather keys
--- @field seconds_to_period_change fun(cfg: table): number Seconds until the next time-of-day period starts
local Json = require("lib.json") ---@class Json

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

--- Parse `hyprctl -j monitors` JSON output into monitors.
--- @param out string|nil raw JSON string
--- @return { name: string, description: string }[]
local function parse_monitors_json(out)
  local decoded = out and Json.decode(out)
  local mons = {}
  if type(decoded) ~= "table" then return mons end
  for _, mon in ipairs(decoded) do
    if type(mon) == "table" and type(mon.name) == "string" then
      table.insert(mons, { name = mon.name, description = type(mon.description) == "string" and mon.description or "" })
    end
  end
  return mons
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

--- Return the active monitors via hyprctl.
--- Tries JSON output first, falls back to text parsing.
--- @param cfg table wallpaper config (used for logging)
--- @param util table shared utility object
--- @return { name: string, description: string }[]
local function monitors(cfg, util)
  local out_json = hyprctl("-j monitors", util)
  local mons = parse_monitors_json(out_json)

  if #mons == 0 then
    local out_txt = hyprctl("monitors | awk '/Monitor/ {print $2}'", util)
    local set = {}
    if out_txt then
      for m in out_txt:gmatch("[^\\n]+") do
        if m:find("%-") and not m:match("^%d+$") then set[m] = true end
      end
    end
    for name, _ in pairs(set) do
      table.insert(mons, { name = name, description = "" })
    end

    if #mons == 0 and (out_json or out_txt) then
      local raw = (out_json or "") .. (out_txt or "")
      util.log("hyprctl output (monitors) empty or unparsable:\n" .. raw, cfg)
      return {}
    end
  end

  return mons
end

--- Set `img` on monitor `mon` through hyprpaper.
--- @param util table shared utility object with `signature` and `log`
--- @param cfg table wallpaper config
--- @param mon string monitor name
--- @param img string absolute image path
--- @return boolean ok
local function set_wallpaper(util, cfg, mon, img)
  local f = io.open(img, "r")
  if not f then
    util.log(string.format("Skipping missing file: %s", img), cfg)
    return false
  end
  f:close()
  local base = util.signature and ("HYPRLAND_INSTANCE_SIGNATURE=" .. util.signature .. " ") or ""
  local rc = os.execute(string.format("%shyprctl hyprpaper wallpaper '%s, %s' >/dev/null 2>&1", base, mon, img))
  if rc ~= 0 and rc ~= true then
    util.log(string.format("hyprpaper wallpaper failed (rc=%s) for %s on %s", tostring(rc), img, mon), cfg)
    return false
  end
  return true
end

--- Apply wallpapers to all active monitors (or `cfg.target_monitor` if set).
--- Monitors whose description has a pin get that image; the rest get a pick from the pool
--- resolved from the current period, season and weather, which avoids every pinned image.
--- @param cfg table wallpaper config
--- @param util table shared utility object
--- @param opts table|nil `{ exclude?, only?, reserved?, history?, pins? }`; monitors in `exclude` are skipped (startup settle) and, when `only` is set, monitors outside it are too; paths in `reserved` (live on other monitors) and `history` (recently shown, oldest first) are avoided when picking; `pins` maps monitor description to image path
--- @return boolean ok false when a monitor needed a pick and the pool had none, or nothing could be applied
--- @return table<string, string> applied map of monitor name to the wallpaper path set this call
--- @return table<string, boolean> pinned monitors in `applied` that got a pin
function Apply.to_monitors(cfg, util, opts)
  opts = opts or {}
  local pins = opts.pins or {}

  local all_mons = monitors(cfg, util)
  if #all_mons == 0 then
    util.log("No monitors found via hyprctl monitors", cfg)
    return false, {}, {}
  end

  local mons = all_mons
  if cfg.target_monitor then
    mons = {}
    for _, mon in ipairs(all_mons) do
      if mon.name == cfg.target_monitor then mons = { mon } end
    end
    if #mons == 0 then
      util.log("Target monitor " .. cfg.target_monitor .. " not in active monitor list; skipping", cfg)
      return true, {}, {}
    end
  end

  -- Startup settle re-runs and pin changes skip monitors that need no new image.
  local wanted = {}
  for _, mon in ipairs(mons) do
    if not (opts.exclude and opts.exclude[mon.name]) and not (opts.only and not opts.only[mon.name]) then
      table.insert(wanted, mon)
    end
  end
  if #wanted == 0 then return true, {}, {} end

  local pinned_paths, auto_names = {}, {}
  for _, mon in ipairs(wanted) do
    if pins[mon.description] then
      pinned_paths[mon.name] = pins[mon.description]
    else
      table.insert(auto_names, mon.name)
    end
  end

  local picks, pool_ok = {}, true
  if #auto_names > 0 then
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
      pool_ok = false
    else
      local reserved = {}
      for path in pairs(opts.reserved or {}) do
        reserved[path] = true
      end
      for _, path in pairs(pins) do
        reserved[path] = true
      end
      picks = pick_wallpapers(files, #auto_names, {
        reserved = reserved,
        history = opts.history,
        favored = favored,
        chance = cfg.weather_chance,
      })
      util.log(
        string.format(
          "Period %s -> %s; monitors=%d; pool=%d; weather=%d",
          label,
          dir_list,
          #auto_names,
          #files,
          #favored
        ),
        cfg
      )
    end
  end

  local targets = {}
  for mon, path in pairs(pinned_paths) do
    util.log(string.format("  pin %s=%s", mon, path), cfg)
    targets[mon] = path
  end
  for i, mon in ipairs(auto_names) do
    if picks[i] then
      util.log(string.format("  pick[%d]=%s", i, picks[i]), cfg)
      targets[mon] = picks[i]
    end
  end

  local applied, pinned = {}, {}
  for mon, img in pairs(targets) do
    img = img:gsub("[\r\n]", "")
    if set_wallpaper(util, cfg, mon, img) then
      applied[mon] = img
      pinned[mon] = pinned_paths[mon] and true or nil
    end
  end
  return pool_ok, applied, pinned
end

--- Active monitors with their descriptions.
--- @param cfg table wallpaper config
--- @param util table shared utility object
--- @return { name: string, description: string }[]
function Apply.list_monitors(cfg, util) return monitors(cfg, util) end

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
