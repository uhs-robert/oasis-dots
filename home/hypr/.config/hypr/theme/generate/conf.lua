-- home/hypr/.config/hypr/theme/generate/conf.lua

local HOME = os.getenv("HOME")
local utils = require("lib.utils")

--- Writes theme.conf to ~/.config/hypr/ with all palette colors as rgb/rgba variables.
--- @param c table Palette color table from theme.colors.*
return function(c)
  local function rgb(hex) return "rgb(" .. hex:gsub("^#", "") .. ")" end
  local function rgba(hex, a) return "rgba(" .. hex:gsub("^#", "") .. a .. ")" end

  local lines = {}
  for key, hex in pairs(c) do
    table.insert(lines, string.format("$%s = %s", key, rgb(hex)))
    table.insert(lines, string.format("$%s_faded = %s", key, rgba(hex, "99")))
  end
  table.sort(lines)

  utils.write_file(HOME .. "/.config/hypr/theme.conf", table.concat(lines, "\n") .. "\n")
end
