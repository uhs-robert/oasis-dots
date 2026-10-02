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
  local folders = {}
  for _, period in ipairs(PERIODS) do
    table.insert(folders, cfg.dirs[period])
  end
  for _, season in ipairs(sorted_keys(cfg.season_dirs or {})) do
    for _, period in ipairs(PERIODS) do
      table.insert(folders, cfg.season_dirs[season][period])
    end
  end
  for _, weather in ipairs(sorted_keys(cfg.weather_dirs or {})) do
    table.insert(folders, cfg.weather_dirs[weather])
  end

  local root = cfg.default_wallpaper_dir or ""
  local used = {}
  print(string.format("Folders (thin = under %d):", THIN))
  for _, dir in ipairs(folders) do
    local files = Apply.list_images(dir)
    for _, f in ipairs(files) do
      used[f] = true
    end
    local name = dir:sub(1, #root + 1) == root .. "/" and dir:sub(#root + 2) or dir
    print(string.format("  %3d  %s%s", #files, name, #files < THIN and "  (thin)" or ""))
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
