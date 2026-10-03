-- home/hypr/.config/hypr/extensions/wallpaper/lib/audit.lua
-- Report folder sizes, images no folder uses, and folders outside the layout

local Apply = require("wallpaper.lib.apply") ---@class Apply

--- @class Audit
--- @field run fun(cfg: table) Print per-folder counts, unused images and unexpected folders
local Audit = {}

local THIN = 3

--- @param keys string[]
--- @return table<string, boolean> folder names of `keys`
local function folder_set(keys)
  local set = {}
  for _, key in ipairs(keys) do
    set[Apply.folder(key)] = true
  end
  return set
end

--- List folders under `root` that do not fit `<Season>/<Period>/<Weather>`.
--- @param root string
--- @return string[] relative paths
local function unexpected_folders(root)
  local seasons = folder_set(Apply.SEASONS)
  seasons[Apply.folder("any")] = true
  local levels = { seasons, folder_set(Apply.PERIODS), folder_set(Apply.WEATHERS) }
  local out = {}
  local p = io.popen(string.format('find -L "%s" -mindepth 1 -type d -printf "%%P\\0" 2>/dev/null', root))
  if not p then return out end
  for rel in (p:read("*a") or ""):gmatch("([^%z]+)") do
    local depth, ok = 0, true
    for part in rel:gmatch("[^/]+") do
      depth = depth + 1
      if not levels[depth] or not levels[depth][part] then ok = false end
    end
    if not ok then table.insert(out, rel) end
  end
  p:close()
  table.sort(out)
  return out
end

--- Print per-folder counts, the images under `cfg.wallpaper_dir` that no folder uses, and stray folders.
--- @param cfg table wallpaper config
function Audit.run(cfg)
  local root = cfg.wallpaper_dir
  local skip = {}
  for _, weather in ipairs(Apply.WEATHERS) do
    table.insert(skip, Apply.folder(weather))
  end
  local seasons = { "any" }
  for _, season in ipairs(Apply.SEASONS) do
    table.insert(seasons, season)
  end

  local used = {}
  local function report(rel, files, flag_thin)
    for _, f in ipairs(files) do
      used[f] = true
    end
    print(string.format("  %3d  %s%s", #files, rel, flag_thin and #files < THIN and "  (thin)" or ""))
  end

  print(string.format("Folders (thin = under %d):", THIN))
  for _, season in ipairs(seasons) do
    for _, period in ipairs(Apply.PERIODS) do
      local rel = Apply.folder(season) .. "/" .. Apply.folder(period)
      report(rel, Apply.list_images(root .. "/" .. rel, skip), true)
      for _, weather in ipairs(Apply.WEATHERS) do
        local nested = rel .. "/" .. Apply.folder(weather)
        local files = Apply.list_images(root .. "/" .. nested)
        if #files > 0 then report(nested, files, false) end
      end
    end
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

  local stray = unexpected_folders(root)
  print(string.format("\nUnexpected folders (%d, outside <Season>/<Period>/<Weather>):", #stray))
  for _, rel in ipairs(stray) do
    print("  " .. rel)
  end
end

return Audit
