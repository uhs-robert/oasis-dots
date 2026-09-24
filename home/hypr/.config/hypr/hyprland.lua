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
local Scripts = require("lib.scripts")

--- Initialises the Hyprland session: applies machine config and loads all subsystems.
local function init()
  Config.setup(Machines.merge(Default))

  require("lua.plugins.hyprvim").setup({
    -- keys = { leader = "SUPER", activate = "V", exit = "ESCAPE" },
    -- The clone tracks main and is pulled by `just update-repos` (run by topgrade).
    updates = { channel = "off" },
    which_key = {
      frontend = Config.shell == "quickshell" and "quickshell" or "eww",
      quickshell_ipc = Scripts.qs_ipc,
      auto_show = { disabled = { "NORMAL", "INSERT", "VISUAL", "V-LINE", "Cursor" } },
    },
  })
end

init()
