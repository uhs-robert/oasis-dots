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
  -- toggle-hypr-errors.sh keeps the errors it hid here; a (re)load brings its own, so the saved ones are stale.
  local runtime_dir = os.getenv("XDG_RUNTIME_DIR")
  if runtime_dir == nil or runtime_dir == "" then runtime_dir = "/tmp" end -- as the script's ${XDG_RUNTIME_DIR:-/tmp}
  os.remove(runtime_dir .. "/hypr-hidden-errors")
  Config.setup(Machines.merge(Default))

  if package.searchpath("lua.plugins.hyprvim", package.path) then
    require("lua.plugins.hyprvim").setup({
      -- keys = { leader = "SUPER", activate = "V", exit = "ESCAPE" },
      -- The clone tracks main and is pulled by `just update-repos` (run by topgrade).
      updates = { channel = "off" },
      which_key = {
        frontend = "quickshell",
        quickshell_ipc = Scripts.qs_ipc,
        delay_ms = Config.input.which_key_delay_ms,
        -- Read after Config.setup has loaded the keymaps, so every submap with a hint bar is in the list.
        auto_show = {
          disabled = require("lib.key.submap_hint").without_whichkey({ "NORMAL", "INSERT", "VISUAL", "V-LINE" }),
        },
      },
      prompt = { frontend = "quickshell" },
      close_handler = Closed.close_addresses,
    })
  else
    require("lib.missing_repos").add("hyprvim (repos/hyprvim)")
  end

  -- Last on purpose: custom/init.lua is the user's own entrypoint, run once everything above is loaded.
  local config_dir = debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./"
  if package.searchpath("custom", config_dir .. "?/init.lua") then require("custom") end
end

init()
