-- home/hypr/.config/hypr/config/init.lua

local Utils = require("lib.utils") ---@class Utils

--- @class Config.Nvidia
--- @field enable boolean Enable NVIDIA-specific fixes and env vars (default: false)
--- @field backend string GBM backend name, e.g. "nvidia-drm" or "nvidia-open" (default: "nvidia-drm")

--- @class Config.Cursor
--- @field theme string Xcursor theme name (default: "xcursor-bibata-original-classic")
--- @field hypr_theme string Hyprcursor theme name (default: "hyprcursor-bibata-original-classic")
--- @field size integer Cursor size in pixels (default: 24)

--- @class Config.App
--- @field term string Terminal emulator command (default: auto-detected)
--- @field editor string Editor command (default: "nvim")
--- @field gui_file_manager string GUI file manager command (default: "dolphin")
--- @field tui_file_manager string TUI file manager command (default: "yazi")
--- @field menu string Menu binary (default: "rofi")
--- @field menu_cmd string Full app-launcher invocation (default: "rofi -name rofiMenu")
--- @field dmenu_cmd string Full dmenu-picker invocation (default: "rofi -name rofiDmenu -i -dmenu")
--- @field display_manager string Display/monitor manager command (default: "wdisplays")

--- @class Config.Monitor
--- @field id integer|nil Monitor id as reported by Hyprland
--- @field name string|nil Monitor name as reported by Hyprland
--- @field description string|nil Monitor description string as reported by Hyprland
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
--- @field is_laptop boolean|nil Whether the system running is a laptop or desktop (default: nil)
--- @field nvidia Config.Nvidia
--- @field cursor Config.Cursor
--- @field app Config.App
--- @field monitors Config.Monitor[] Ordered list of monitors; position in list maps to jump index 1–9
--- @field devices HL.DeviceSpec[] Per-device configs applied via hl.device() on startup (default: {})
local Config = {}

Config.defaults = {
  leader = "SUPER",
  theme = "oasis_moonlight",
  ws_per_monitor = 5,
  persistent_workspaces = 5,
  vim_mode = true,
  use_uwsm = false,
  drm_devices = nil,
  is_laptop = nil,
  nvidia = {
    enable = nil,
    backend = nil,
  },
  cursor = {
    theme = "xcursor-bibata-original-classic",
    hypr_theme = "hyprcursor-bibata-original-classic",
    size = 24,
  },
  app = {
    term = nil,
    term_cmd = nil,
    editor = "nvim",
    gui_file_manager = "dolphin",
    tui_file_manager = "yazi",
    menu = "rofi",
    menu_cmd = nil,
    dmenu_cmd = nil,
    display_manager = "wdisplays",
  },
  monitors = {}, --- @type Config.Monitor[]
  devices = {}, --- @type HL.DeviceSpec[]
}

--- @return string|nil
local function detect_term()
  local candidates = { "foot", "kitty", "ghostty", "wezterm", "alacritty", "xterm", "konsole" }
  local dirs = {}
  for dir in (os.getenv("PATH") or ""):gmatch("[^:]+") do
    dirs[#dirs + 1] = dir
  end
  for _, term in ipairs(candidates) do
    for _, dir in ipairs(dirs) do
      local f = io.open(dir .. "/" .. term, "r")
      if f then
        f:close()
        return term
      end
    end
  end
end

local TERM_CMDS = {
  ghostty = "ghostty +new-window",
  foot = "footclient",
  alacritty = "alacritty",
  kitty = "kitty --single-instance",
  wezterm = "wezterm start",
  xterm = "xterm",
  konsole = "konsole",
}

--- @return string|nil
local function detect_term_cmd(term)
  if term == nil then return nil end
  return TERM_CMDS[term] or term
end

--- @return boolean
local function detect_nvidia()
  local f = io.open("/dev/nvidia0", "r")
  if f then
    f:close()
    return true
  end
  local m = io.open("/sys/module/nvidia/version", "r")
  if m then
    m:close()
    return true
  end
  return false
end

--- @return string
local function detect_nvidia_backend()
  local f = io.open("/proc/driver/nvidia/version", "r")
  if f then
    local v = f:read("*a")
    f:close()
    if v:match("Open") then return "nvidia-open" end
  end
  return "nvidia-drm"
end

--- Detects laptop by checking live monitors for an eDP- panel.
--- Returns nil when the hl API is unavailable (e.g. during unit tests).
--- @return boolean|nil
local function detect_is_laptop()
  for _, mon in ipairs(hl.get_monitors()) do
    if mon.name:sub(1, 4) == "eDP-" then return true end
  end

  -- hl.get_monitors() may return empty at initial startup before Hyprland is ready;
  -- fall back to kernel DRM connector list
  local drm = io.popen("ls /sys/class/drm/ 2>/dev/null")
  if drm then
    for entry in drm:lines() do
      if entry:match("^card%d+%-eDP") then
        drm:close()
        return true
      end
    end
    drm:close()
  end

  return false
end

--- Resolves monitors to a list, calling the factory function when provided.
--- @param monitors Config.Monitor[]|fun(is_laptop: boolean|nil): Config.Monitor[]
--- @param is_laptop boolean|nil
--- @return Config.Monitor[]
local function resolve_monitors(monitors, is_laptop)
  if type(monitors) == "function" then return monitors(is_laptop) end

  return monitors
end

--- Fills in menu_cmd and dmenu_cmd defaults derived from app.menu when absent.
--- @param app Config.App
local function fill_menu_cmds(app)
  local m = app.menu
  if not app.menu_cmd then app.menu_cmd = m .. " -name rofiMenu" end
  if not app.dmenu_cmd then app.dmenu_cmd = m .. " -name rofiDmenu -i -dmenu" end
end

--- Writes a thin wrapper script so any subprocess can call `term -e cmd`
--- without knowing the emulator's flags.
--- @param term_cmd string
local function write_term_wrapper(term_cmd)
  local home = os.getenv("HOME")
  local path = home .. "/.config/hypr/scripts/term"
  local f = io.open(path, "w")
  if not f then return end
  f:write("#!/bin/sh\nexec " .. term_cmd .. ' "$@"\n')
  f:close()
  os.execute("chmod +x " .. path)
end

--- Derives fields that are dependent upon other config values.
--- @param cfg table
local function derive(cfg)
  if cfg.app.term == nil then cfg.app.term = detect_term() end
  if cfg.app.term_cmd == nil then cfg.app.term_cmd = detect_term_cmd(cfg.app.term) end
  write_term_wrapper(cfg.app.term_cmd)
  if cfg.is_laptop == nil then cfg.is_laptop = detect_is_laptop() end
  if cfg.nvidia.enable == nil then
    cfg.nvidia.enable = detect_nvidia()
    if cfg.nvidia.enable and cfg.nvidia.backend == nil then cfg.nvidia.backend = detect_nvidia_backend() end
  end
  if cfg.nvidia.backend == nil then cfg.nvidia.backend = "nvidia-drm" end
  cfg.monitors = resolve_monitors(cfg.monitors, cfg.is_laptop)
  fill_menu_cmds(cfg.app)
end

--- @param devices HL.DeviceSpec[]
local function set_device_settings(devices)
  for _, device in ipairs(devices) do
    hl.device(device)
  end
end

--- Deep-merges a partial config patch onto the live config and re-derives dependent fields.
--- @param patch table
--- @return Config
Config.update = function(patch)
  Utils.deep_extend(Config, patch)
  derive(Config)

  return Config
end

--- Resets to defaults, applies overrides, and writes the result onto this module table.
--- @param overrides table|nil
--- @return Config
Config.merge = function(overrides)
  local merged = Utils.deep_extend({}, Config.defaults)
  if overrides then Utils.deep_extend(merged, overrides) end
  derive(merged)
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
  Config = Config.merge(overrides)
  hl.on("hyprland.start", require("config.autostart"))
  require("config.env")
  require("keymaps")
  require("config.general")
  set_device_settings(Config.devices)
  require("config.rules")
  require("config.monitors")
  require("theme")
  require("extensions")

  return Config
end

return Config
