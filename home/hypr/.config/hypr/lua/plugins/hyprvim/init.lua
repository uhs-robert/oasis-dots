-- Bootstrap hyprvim
local path = os.getenv("HOME") .. "/.local/share/hyprland/lua/plugins/hyprvim/init.lua"

local chunk, err = loadfile(path)

if not chunk then error(err) end

return chunk()
