-- home/hypr/.config/hypr/extensions/wallpaper/lib/audit.lua
-- Report folder sizes and images that no folder uses

local Apply = require("wallpaper.lib.apply") ---@class Apply

--- @class Audit
--- @field run fun(cfg: table) Print per-folder counts and the images in no folder
local Audit = {}

local PERIODS = { "morning", "day", "evening", "night" }
local THIN = 3

--- @param t table
--- @return string[] keys in alphabetical order
local function sorted_keys(t)
  local keys = {}
  for k in pairs(t) do
    table.insert(keys, k)
  end
  table.sort(keys)
  return keys
end

--- Print per-folder counts and the images under `cfg.default_wallpaper_dir` that no folder uses.
--- @param cfg table wallpaper config
function Audit.run(cfg)
  local period_folders = {}
  for _, period in ipairs(PERIODS) do
    table.insert(period_folders, cfg.dirs[period])
  end
  for _, season in ipairs(sorted_keys(cfg.season_dirs or {})) do
    for _, period in ipairs(PERIODS) do
      table.insert(period_folders, cfg.season_dirs[season][period])
    end
  end

  local names = Apply.weather_names(cfg)
  local kinds = sorted_keys(names)
  local skip = {}
  for _, kind in ipairs(kinds) do
    table.insert(skip, names[kind])
  end

  local root = cfg.default_wallpaper_dir or ""
  local used = {}

  --- @param dir string
  --- @param files string[]
  --- @param flag_thin boolean
  local function report(dir, files, flag_thin)
    for _, f in ipairs(files) do
      used[f] = true
    end
    local name = dir:sub(1, #root + 1) == root .. "/" and dir:sub(#root + 2) or dir
    print(string.format("  %3d  %s%s", #files, name, flag_thin and #files < THIN and "  (thin)" or ""))
  end

  print(string.format("Folders (thin = under %d):", THIN))
  for _, dir in ipairs(period_folders) do
    report(dir, Apply.list_images(dir, skip), true)
    for _, kind in ipairs(kinds) do
      local nested = dir .. "/" .. names[kind]
      local files = Apply.list_images(nested)
      if #files > 0 then report(nested, files, false) end
    end
  end
  for _, kind in ipairs(kinds) do
    report(cfg.weather_dirs[kind], Apply.list_images(cfg.weather_dirs[kind]), true)
  end

  local unused = {}
  for _, f in ipairs(Apply.list_images(root)) do
    if not used[f] then table.insert(unused, f) end
  end
  table.sort(unused)
  print(string.format("\nUnused (%d, in no folder):", #unused))
  for _, f in ipairs(unused) do
    print("  " .. f)
  end
end

return Audit
