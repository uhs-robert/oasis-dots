-- home/hypr/.config/hypr/config/init.lua

local utils = require("lib.utils")

--- @class Config.Nvidia
--- @field enable boolean Enable NVIDIA-specific fixes and env vars (default: false)
--- @field backend string GBM backend name, e.g. "nvidia-drm" or "nvidia-open" (default: "nvidia-drm")

--- @class Config.Cursor
--- @field theme string Xcursor theme name (default: "breeze_cursors")
--- @field hypr_theme string Hyprcursor theme name (default: "breeze-dark")
--- @field size integer Cursor size in pixels (default: 24)

--- @class Config.App
--- @field term string Terminal emulator command (default: "kitty")
--- @field editor string Editor command (default: "nvim")
--- @field gui_file_manager string GUI file manager command (default: "dolphin")
--- @field tui_file_manager string TUI file manager command (default: "yazi")
--- @field menu string Menu binary (default: "rofi")
--- @field menu_cmd string Full app-launcher invocation (default: "rofi -name rofiMenu")
--- @field dmenu_cmd string Full dmenu-picker invocation (default: "rofi -name rofiDmenu -i -dmenu")
--- @field display_manager string Display/monitor manager command (default: "wdisplays")

--- @class Config.Monitor
--- @field description string Monitor description string as reported by Hyprland
--- @field mode string Resolution and refresh rate, e.g. "2560x1440@144"
--- @field position string Position in the virtual desktop, e.g. "1920x0"
--- @field scale number DPI scale factor
--- @field transform integer|nil Transform (rotation), e.g. 3 for 270°

--- @class Config
--- @field leader string Modifier key for keybinds (default: "SUPER")
--- @field theme string Name of the theme file in ./theme/themes/ (default: "oasis_moonlight")
--- @field ws_per_monitor integer Workspaces assigned per monitor on startup (default: 5)
--- @field persistent_workspaces integer|boolean Workspaces to pin per monitor, or false to disable (default: 5)
--- @field vim_mode boolean Use H/J/K/L as directional inputs in keybinds (default: true)
--- @field use_uwsm boolean Enable uwsm session management (default: false)
--- @field drm_devices string|nil DRM device path(s) for WLR_DRM_DEVICES; nil = unset (default: nil)
--- @field nvidia Config.Nvidia
--- @field cursor Config.Cursor
--- @field app Config.App
--- @field monitors Config.Monitor[] Ordered list of monitors; position in list maps to jump index 1–9
local Config = {}

Config.defaults = {
  leader = "SUPER",
  theme = "oasis_moonlight",
  ws_per_monitor = 5,
  persistent_workspaces = 5,
  vim_mode = true,
  use_uwsm = false,
  drm_devices = nil,
  nvidia = {
    enable = false,
    backend = "nvidia-drm",
  },
  cursor = {
    theme = "breeze_cursors",
    hypr_theme = "breeze-dark",
    size = 24,
  },
  app = {
    term = "kitty",
    editor = "nvim",
    gui_file_manager = "dolphin",
    tui_file_manager = "yazi",
    menu = "rofi",
    menu_cmd = nil,
    dmenu_cmd = nil,
    display_manager = "wdisplays",
  },
  monitors = {}, --- @type Config.Monitor[]
}

Config.update = function(overrides)
  local merged = utils.deep_extend({}, Config.defaults)
  if overrides then utils.deep_extend(merged, overrides) end
  local m = merged.app.menu
  if not merged.app.menu_cmd then merged.app.menu_cmd = m .. " -name rofiMenu" end
  if not merged.app.dmenu_cmd then merged.app.dmenu_cmd = m .. " -name rofiDmenu -i -dmenu" end
  for k, v in pairs(merged) do
    Config[k] = v
  end

  return Config
end

--- Merges user overrides into defaults and writes the result onto this module table.
--- After calling setup(), any module that does require("config") gets the configured values.
--- Arrays (monitors) and nil values (drm_devices) are replaced wholesale, not merged.
--- @param overrides table|nil
--- @return Config
Config.setup = function(overrides)
  Config = Config.update(overrides)
  hl.on("hyprland.start", require("config.system.autostart"))
  require("config.system.env")
  require("config.system.general")
  -- require("config.system.devices") -- TODO: Implement config for devices to pass here and add device specific settings
  require("config.system.rules")
  require("config.system.monitors")
  require("config.system.keys")
  require("theme")
  require("mods")

  return Config
end

return Config
