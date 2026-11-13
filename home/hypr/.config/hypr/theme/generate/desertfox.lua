local Config = require("config") ---@class Config
local fallback = require("theme.fallback")

--- Tells DesertFox the desktop theme name with `desertfox theme <name>`, on every reload.
--- Best effort: it runs in the background with its output dropped, and skips silently when the CLI is missing or no
--- browser is listening. Generate.all has no pcall, so nothing here may raise. A theme change while the browser is
--- closed is not replayed until the next reload.
--- The name is Config.theme, except when theme/init.lua fell back to the embedded palette: Config.theme then still
--- holds the missing name, which DesertFox does not know, so the palette actually rendered is pushed.
--- @param c table Palette color table, the embedded fallback when the saved palette could not load
return function(c)
  local ok, err = pcall(function()
    local name = c == fallback and "oasis_moonlight" or Config.theme
    if type(name) ~= "string" or name == "" then return end
    -- Hyprland's PATH carries ~/.local/bin (config/env), so the bare name resolves.
    os.execute(
      string.format(
        "command -v desertfox >/dev/null 2>&1 && desertfox theme '%s' >/dev/null 2>&1 &",
        name:gsub("'", "'\\''")
      )
    )
  end)
  if not ok then io.stderr:write("theme.generate.desertfox: " .. tostring(err) .. "\n") end
end
