-- home/hypr/.config/hypr/config/system/env.lua
--- Sets Wayland, Qt, cursor, and XDG environment variables. Conditionally applies NVIDIA-specific vars.

local Config = require("config")
local HOME = os.getenv("HOME")

--- Iterates over env_settings and registers each key/value pair via hl.env().
--- @param env_settings table<string, string|number>
local set_env = function(env_settings)
  for key, value in pairs(env_settings) do
    hl.env(key, value)
  end
end

-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Environment-variables/
local env = {
  PATH = table.concat({
    HOME .. "/.cargo/bin",
    HOME .. "/.local/bin",
    HOME .. "/.config/hypr/scripts",
    "/usr/local/bin",
    "/usr/bin",
    "/bin",
  }, ":"),
  GTK_THEME = "Breeze-Dark",
  XCURSOR_THEME = Config.cursor.theme,
  XCURSOR_SIZE = tostring(Config.cursor.size),
  QT_QPA_PLATFORMTHEME = "qt5ct", -- for Qt apps
  QT_QPA_PLATFORM = "wayland;xcb",
  QT_AUTO_SCREEN_SCALE_FACTOR = 1,
  HYPRCURSOR_THEME = Config.cursor.hypr_theme,
  HYPRCURSOR_SIZE = tostring(Config.cursor.size),
  XDG_CURRENT_DESKTOP = "Hyprland",
  XDG_SESSION_TYPE = "wayland",
  XDG_SESSION_DESKTOP = "Hyprland",
  TERMINAL = Config.app.term,
}
if Config.drm_devices then env.WLR_DRM_DEVICES = Config.drm_devices end

-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Environment-variables/#nvidia-specific
local nvidia_env = {
  GBM_BACKEND = Config.nvidia.backend,
  __GLX_VENDOR_LIBRARY_NAME = "nvidia",
  LIBVA_DRIVER_NAME = "nvidia",
  __GL_GSYNC_ALLOWED = "1",
  __GL_VRR_ALLOWED = "0",

  __VK_LAYER_NV_optimus = "NVIDIA_only",
  __NV_PRIME_RENDER_OFFLOAD = "1",
}

--- Registers all environment variables; nvidia_env is added only when NVIDIA is enabled.
local function init()
  set_env(env)
  if Config.nvidia.enable then set_env(nvidia_env) end
end

init()
