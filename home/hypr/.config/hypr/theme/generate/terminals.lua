-- home/hypr/.config/hypr/theme/generate/terminals.lua

local HOME = os.getenv("HOME")
local Config = require("config") ---@class Config

--- Replaces the first line matching `prefix` with `new_line` in `path`.
--- @param path string
--- @param prefix string Plain-string prefix to match (no patterns)
--- @param new_line string Replacement line (no trailing newline)
local function replace_line(path, prefix, new_line)
  local f = io.open(path, "r")
  if not f then return end
  local lines, changed = {}, false
  for line in f:lines() do
    if not changed and line:sub(1, #prefix) == prefix then
      table.insert(lines, new_line)
      changed = true
    else
      table.insert(lines, line)
    end
  end
  f:close()
  if not changed then return end
  local out = io.open(path, "w")
  if not out then return end
  out:write(table.concat(lines, "\n") .. "\n")
  out:close()
end

--- Updates terminal and app theme config files to match the active palette.
--- Kitty and tmux reload live; others pick up the change on next launch.
--- @param _c table Unused, theme name comes from Config.theme
return function(_c)
  local name = Config.theme -- e.g. "oasis_moonlight"
  local dark = name .. "_dark" -- e.g. "oasis_moonlight_dark"
  local dashed = name:gsub("_", "-") -- e.g. "oasis-moonlight"

  -- Terminals
  replace_line(HOME .. "/.config/ghostty/config", "theme = ", string.format('theme = "%s"', dark))
  replace_line(
    HOME .. "/.config/kitty/dark-theme.auto.conf",
    "include ",
    string.format("include ~/.config/kitty/themes/%s.conf", dark)
  )
  replace_line(
    HOME .. "/.config/foot/foot.ini",
    "include=",
    string.format("include=~/.config/foot/themes/%s.ini", name)
  )

  -- tmux: flavor is just the variant without the "oasis_" prefix
  local tmux_flavor = name:gsub("^oasis_", "") .. "_dark" -- e.g. "moonlight_dark"
  replace_line(HOME .. "/.tmux.conf", "set -g @oasis_flavor ", string.format('set -g @oasis_flavor "%s"', tmux_flavor))

  -- yazi: uses dash-separated names with a -dark suffix
  replace_line(HOME .. "/.config/yazi/theme.toml", "dark = ", string.format('dark = "%s-dark"', dashed))

  -- Live reloads
  os.execute("kitty @ set-colors --all --configured >/dev/null 2>&1 &")
  os.execute("tmux source-file ~/.tmux.conf >/dev/null 2>&1 &")
end
