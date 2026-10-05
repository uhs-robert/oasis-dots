-- home/hypr/.config/hypr/theme/generate/nvim.lua

local Config = require("config") ---@class Config
local Utils = require("lib.utils") ---@class Utils
local StateDir = require("lib.state")

--- Hands Neovim the oasis.nvim colorscheme matching the palette while Settings > Colors > Sync Neovim is on.
--- Neovim reads `nvim-colorscheme` at startup; running instances switch over their RPC sockets. With sync
--- off the file is removed, so Neovim falls back to its own scheme.
--- @param _c table Unused, the scheme name comes from Config.theme
return function(_c)
  local state_dir = StateDir()
  local scheme_file = state_dir .. "/nvim-colorscheme"
  local flag = io.open(state_dir .. "/nvim_sync", "r")
  local sync_on = flag ~= nil and flag:read("*line") == "on"
  if flag then flag:close() end

  if not sync_on then
    os.remove(scheme_file)
    return
  end

  local scheme = Config.theme:gsub("_", "-") -- e.g. "oasis-moonlight"
  if not Utils.write_file_if_changed(scheme_file, scheme .. "\n") then return end
  -- Every Neovim listens on $XDG_RUNTIME_DIR/nvim.<pid>.0 by default.
  os.execute(
    string.format(
      [[for s in "${XDG_RUNTIME_DIR:-/tmp}"/nvim.*.0; do [ -S "$s" ] && nvim --server "$s" --remote-expr 'execute("colorscheme %s")'; done >/dev/null 2>&1 &]],
      scheme
    )
  )
end
