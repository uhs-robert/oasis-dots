local Config = require("config") ---@class Config

--- Tells DesertFox the desktop palette name with `desertfox theme <name>`, on every reload.
--- Best effort: it runs in the background with its output dropped, and skips silently when the CLI is missing or no
--- browser is listening. Generate.all has no pcall, so nothing here may raise. A theme change while the browser is
--- closed is not replayed until the next reload.
--- @param _c table Unused, the palette name comes from Config.theme
return function(_c)
  local ok, err = pcall(function()
    local name = Config.theme
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
