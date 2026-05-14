#!/usr/bin/env lua
-- home/hypr/.config/hypr/mods/hyprlockshot/init.lua

local cache_dir = (os.getenv("XDG_CACHE_HOME") or (os.getenv("HOME") .. "/.cache")) .. "/hyprlock"
os.execute("mkdir -p " .. cache_dir)
os.execute("rm -f " .. cache_dir .. "/*.png")

local backgrounds = {}

local handle = io.popen("hyprctl -j monitors | jq -r '.[] | select(.disabled == false) | [.name, .description] | @tsv'")
if handle then
  for line in handle:lines() do
    local name, desc = line:match("([^\t]+)\t(.*)")
    if name then
      local path = cache_dir .. "/" .. name .. ".png"
      os.execute(string.format("grim -o %s %s >/dev/null 2>&1", name, path))
      table.insert(
        backgrounds,
        string.format(
          "background {\n  monitor = desc:%s\n  path = %s\n  blur_passes = 1\n  brightness = 0.6172\n  color = $bg_core_faded\n}",
          desc,
          path
        )
      )
    end
  end
  handle:close()
end

local f = io.open(cache_dir .. "/backgrounds.conf", "w")
if f then
  f:write(table.concat(backgrounds, "\n\n") .. "\n")
  f:close()
end

local extra_args = table.concat(arg, " ")
os.execute("hyprlock --immediate-render --no-fade-in " .. extra_args)
