-- home/hypr/.config/hypr/hyprland.lua
--
--    ██╗  ██╗██╗   ██╗██████╗ ██████╗ ██╗      █████╗ ███╗   ██╗██████╗
--    ██║  ██║╚██╗ ██╔╝██╔══██╗██╔══██╗██║     ██╔══██╗████╗  ██║██╔══██╗
--    ███████║ ╚████╔╝ ██████╔╝██████╔╝██║     ███████║██╔██╗ ██║██║  ██║
--    ██╔══██║  ╚██╔╝  ██╔═══╝ ██╔══██╗██║     ██╔══██║██║╚██╗██║██║  ██║
--    ██║  ██║   ██║   ██║     ██║  ██║███████╗██║  ██║██║ ╚████║██████╔╝
--    ╚═╝  ╚═╝   ╚═╝   ╚═╝     ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═════╝
--

local Config = require("config") ---@class Config
local Machines = require("config.machines")
local Default = require("config.machines.default")

--- Initialises the Hyprland session: applies machine config and loads all subsystems.
local function init()
  Config.setup(Machines.merge(Default))

  -- A linked dev checkout must stay on its branch, so skip tag-based updates there.
  local link = io.popen('readlink "$HOME/.local/share/dotfiles/repos/hyprvim"')
  local dev_checkout = link and (link:read("l") or "") ~= ""
  if link then link:close() end

  require("lua.plugins.hyprvim").setup({
    -- keys = { leader = "SUPER", activate = "V", exit = "ESCAPE" },
    updates = { channel = dev_checkout and "off" or "stable" },
    which_key = {
      auto_show = { disabled = { "NORMAL", "INSERT", "VISUAL", "V-LINE", "Cursor" } },
    },
  })
end

init()
