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
local Closed = require("lib.closed_windows")

--- Initialises the Hyprland session: applies machine config, loads all subsystems, then the user's custom/init.lua.
local function init()
  Config.setup(Machines.merge(Default))

  local has_hyprvim, hyprvim = pcall(require, "lua.plugins.hyprvim")
  if not has_hyprvim then require("lib.missing_repos").add("hyprvim (repos/hyprvim)") end
  if has_hyprvim then
    hyprvim.setup({
      -- keys = { leader = "SUPER", activate = "V", exit = "ESCAPE" },
      -- The clone tracks main and is pulled by `just update-repos` (run by topgrade).
      updates = { channel = "off" },
      which_key = {
        frontend = "quickshell",
        quickshell_ipc = Scripts.qs_ipc,
        auto_show = { disabled = { "NORMAL", "INSERT", "VISUAL", "V-LINE", "Cursor" } },
      },
      prompt = { frontend = "quickshell" },
      close_handler = Closed.close_addresses,
    })
  end

  -- Last on purpose: custom/init.lua is the user's own entrypoint, run once everything above is loaded.
  local config_dir = debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./"
  if package.searchpath("custom", config_dir .. "?/init.lua") then require("custom") end
end

init()
