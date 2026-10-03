-- home/hypr/.config/hypr/theme/generate/terminals.lua

local HOME = os.getenv("HOME")
local Config = require("config") ---@class Config
local Utils = require("lib.utils") ---@class Utils

--- Writes `dst` from the `src` template with the first line starting with `prefix` replaced by `new_line`.
--- @param src string
--- @param dst string
--- @param prefix string Plain-string prefix to match (no patterns)
--- @param new_line string Replacement line (no trailing newline)
--- @return boolean changed
local function render_template(src, dst, prefix, new_line)
  local f = io.open(src, "r")
  if not f then return false end
  local lines, replaced = {}, false
  for line in f:lines() do
    if not replaced and line:sub(1, #prefix) == prefix then
      table.insert(lines, new_line)
      replaced = true
    else
      table.insert(lines, line)
    end
  end
  f:close()
  if not replaced then return false end
  return Utils.write_file_if_changed(dst, table.concat(lines, "\n") .. "\n")
end

--- Updates terminal and app theme config files to match the active palette.
--- Kitty and tmux reload live; others pick up the change on next launch.
--- @param _c table Unused, theme name comes from Config.theme
return function(_c)
  local name = Config.theme -- e.g. "oasis_moonlight"
  local dark = name .. "_dark" -- e.g. "oasis_moonlight_dark"
  local dashed = name:gsub("_", "-") -- e.g. "oasis-moonlight"

  local changed = {}

  -- Terminals
  Utils.write_file_if_changed(HOME .. "/.config/ghostty/oasis-theme.conf", string.format('theme = "%s"\n', dark))
  changed.kitty = Utils.write_file_if_changed(
    HOME .. "/.config/kitty/oasis-theme.conf",
    string.format("include ~/.config/kitty/themes/%s.conf\n", dark)
  )
  render_template(
    HOME .. "/.config/foot/foot.template.ini",
    HOME .. "/.config/foot/foot.ini",
    "include=",
    string.format("include=~/.config/foot/themes/%s.ini", name)
  )

  -- tmux: flavor is just the variant without the "oasis_" prefix
  local tmux_flavor = name:gsub("^oasis_", "") .. "_dark" -- e.g. "moonlight_dark"
  changed.tmux =
    Utils.write_file_if_changed(HOME .. "/.tmux.oasis.conf", string.format('set -g @oasis_flavor "%s"\n', tmux_flavor))

  -- yazi: uses dash-separated names with a -dark suffix
  render_template(
    HOME .. "/.config/yazi/theme.template.toml",
    HOME .. "/.config/yazi/theme.toml",
    "dark = ",
    string.format('dark = "%s-dark"', dashed)
  )

  -- Live reloads
  if changed.kitty then
    local file = string.format("%s/.config/kitty/themes/%s.conf", HOME, dark)
    os.execute(
      string.format(
        'for s in "${XDG_RUNTIME_DIR:-/tmp}"/kitty-*; do [ -S "$s" ] && kitty @ --to "unix:$s" set-colors --all --configured %q; done >/dev/null 2>&1 &',
        file
      )
    )
  end
  if changed.tmux then os.execute("tmux source-file ~/.tmux.conf >/dev/null 2>&1 &") end
end
