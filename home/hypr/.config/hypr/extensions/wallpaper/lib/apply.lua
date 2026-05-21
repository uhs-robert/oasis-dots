-- home/hypr/.config/hypr/extensions/wallpaper/lib/apply.lua
-- Period resolution, file selection, and hyprpaper application

--- @class Apply
--- @field to_monitors fun(cfg: table, util: table): boolean Apply wallpapers to all active monitors (or cfg.target_monitor if set); returns true on success
--- @field list_images fun(dir: string): string[] Public wrapper around list_images for external callers
local Apply = {}

--- Find all image files under `dir` (recursive, follows symlinks).
--- @param dir string absolute path to search
--- @return string[] list of absolute file paths
local function list_images(dir)
  -- Use -print0 to safely handle spaces/newlines
  local cmd = string.format(
    'find -L "%s" -type f \\( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.webp" -o -iname "*.bmp" \\) -print0',
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

--- Pick `count` wallpapers from `dir`, cycling if fewer files exist.
--- @param dir string directory to pick from
--- @param count integer number of wallpapers needed
--- @return string[] selected file paths (may be empty if dir has none)
local function pick_wallpapers(dir, count)
  local files = list_images(dir)
  if #files == 0 then return {} end
  shuffle(files)
  local out = {}
  for i = 1, count do
    out[i] = files[((i - 1) % #files) + 1]
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

--- Resolve which directory to use for the given period.
--- Prefers `cfg.force_dir`, then the period-specific dir (if non-empty),
--- then `cfg.default_wallpaper_dir`, then the period dir regardless.
--- @param cfg table wallpaper config
--- @param period string period name key into `cfg.dirs`
--- @return string|nil resolved directory path
local function resolve_dir(cfg, period)
  if cfg.force_dir then return cfg.force_dir end
  local candidate = cfg.dirs[period]
  if candidate and #list_images(candidate) > 0 then return candidate end
  if cfg.default_wallpaper_dir then return cfg.default_wallpaper_dir end
  return candidate
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
--- Resolves the wallpaper directory from the current time-of-day period,
--- picks one image per monitor, preloads via hyprpaper, then sets each.
--- @param cfg table wallpaper config
--- @param util table shared utility object
--- @return boolean true on success, false if nothing could be applied
function Apply.to_monitors(cfg, util)
  local period, dir

  -- Use time-of-day periods only if enabled
  if cfg.time_of_day_enabled then
    period = current_period(cfg)
    dir = resolve_dir(cfg, period)
  else
    -- Skip time-of-day logic, use default directory directly
    period = "default"
    dir = cfg.force_dir or cfg.default_wallpaper_dir
  end

  if not dir then
    util.log("No directory resolved for period " .. period, cfg)
    return false
  end

  local mons = monitors(cfg, util)
  if #mons == 0 then
    util.log("No monitors found via hyprctl monitors", cfg)
    return false
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
      return true
    end

    -- Skip monitors that already have a wallpaper set (e.g. rotation loop beat us to it)
    local active = hyprctl("hyprpaper listactive", util) or ""
    if active:find(cfg.target_monitor .. ":", 1, true) then
      util.log("Monitor " .. cfg.target_monitor .. " already has wallpaper; skipping", cfg)
      return true
    end

    mons = { cfg.target_monitor }
  end

  local picks = pick_wallpapers(dir, #mons)
  if #picks == 0 then
    util.log("No wallpapers found in " .. dir .. " (period " .. period .. ")", cfg)
    return false
  end

  util.log(string.format("Period %s -> dir %s; monitors=%d; wallpapers=%d", period, dir, #mons, #picks), cfg)
  if cfg.verbose then
    for i, img in ipairs(picks) do
      util.log(string.format("  pick[%d]=%s", i, img), cfg)
    end
  end

  for i, mon in ipairs(mons) do
    local img = picks[i]
    if img then
      -- sanitize path (remove embedded newlines) and ensure absolute
      img = img:gsub("[\r\n]", "")
      -- ensure file exists
      local f = io.open(img, "r")
      if not f then
        -- Try relative to dir as fallback
        local alt = dir .. "/" .. img
        f = io.open(alt, "r")
        if f then img = alt end
      end
      if not f then
        util.log(string.format("Skipping missing file: %s", img), cfg)
      else
        f:close()
        local base = util.signature and ("HYPRLAND_INSTANCE_SIGNATURE=" .. util.signature .. " ") or ""
        local rc1 = os.execute(string.format("%shyprctl hyprpaper preload '%s' >/dev/null 2>&1", base, img))
        if rc1 ~= 0 and rc1 ~= true then
          util.log(string.format("hyprpaper preload failed (rc=%s) for %s", tostring(rc1), img), cfg)
        end
        util.sleep(0.15)
        local rc2 = os.execute(string.format("%shyprctl hyprpaper wallpaper '%s,%s' >/dev/null 2>&1", base, mon, img))
        if rc2 ~= 0 and rc2 ~= true then
          util.log(string.format("hyprpaper wallpaper failed (rc=%s) for %s on %s", tostring(rc2), img, mon), cfg)
        end
      end
    end
  end
  local base = util.signature and ("HYPRLAND_INSTANCE_SIGNATURE=" .. util.signature .. " ") or ""
  os.execute(string.format("%shyprctl hyprpaper unload unused >/dev/null 2>&1", base))
  return true
end

--- Public wrapper around `list_images` for external callers.
--- @param dir string directory to scan
--- @return string[] image file paths
function Apply.list_images(dir)
  return list_images(dir)
end

return Apply
