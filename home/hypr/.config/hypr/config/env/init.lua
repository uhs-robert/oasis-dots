--- Sets Wayland, Qt, cursor, and XDG environment variables. Conditionally applies NVIDIA-specific and PRIME offload vars.

local Config = require("config") ---@class Config
local HOME = os.getenv("HOME")

--- Iterates over env_settings and registers each key/value pair via hl.env().
--- @param env_settings table<string, string|number>
local set_env = function(env_settings)
  for key, value in pairs(env_settings) do
    hl.env(key, value)
  end
end

--- True when path names an existing file or directory (fopen succeeds on a directory on Linux).
--- @param path string
--- @return boolean
local function exists(path)
  local handle = io.open(path, "r")
  if not handle then return false end
  handle:close()
  return true
end

--- An .npmrc value as npm's ini parser reads it: surrounding quotes removed, else cut at a ; or # comment.
--- @param raw string
--- @return string
local function npmrc_value(raw)
  local quoted = raw:match('^"(.*)"$') or raw:match("^'(.*)'$")
  if quoted then return quoted end
  return (raw:gsub("%s*[;#].*$", ""))
end

--- Expands ${VAR} and a leading ~ as npm does. Nil when a variable is unset, where npm refuses the config too.
--- @param value string
--- @return string|nil
local function npm_expand(value)
  local unset = false
  value = value:gsub("%${([%w_]+)}", function(name)
    local got = os.getenv(name)
    if not got then unset = true end
    return got or ""
  end)
  if unset then return nil end
  return (value:gsub("^~/", HOME .. "/"))
end

--- The bin dir of npm's global prefix: $NPM_CONFIG_PREFIX (either case), else the last prefix= line of ~/.npmrc.
--- Nil without either, since npm's default prefix (/usr) is already on PATH.
--- @return string|nil
local function npm_global_bin()
  local prefix = os.getenv("npm_config_prefix") or os.getenv("NPM_CONFIG_PREFIX")
  if not prefix or prefix == "" then
    local npmrc = io.open(HOME .. "/.npmrc", "r")
    if not npmrc then return nil end
    for line in npmrc:lines() do
      local raw = line:match("^%s*prefix%s*=%s*(.-)%s*$")
      if raw then prefix = npmrc_value(raw) end
    end
    npmrc:close()
  end
  if not prefix or prefix == "" then return nil end
  prefix = npm_expand(prefix)
  if not prefix or prefix == "" then return nil end
  return prefix .. "/bin"
end

--- The agent shims (when the agents package is stowed), Config.path_prepend, npm's global bin and the config's own
--- dirs, ahead of the inherited PATH, without duplicates.
--- @return string
local function build_path()
  local dirs = {}
  -- First of all, so an agent started from the desktop finds its shim (and runs in agents.slice) before the real one.
  local agent_shims = HOME .. "/.local/share/agent-shims/bin"
  if exists(agent_shims) then dirs[#dirs + 1] = agent_shims end
  for _, dir in ipairs(Config.path_prepend or {}) do
    dirs[#dirs + 1] = dir
  end
  -- Without it agent-shims, run by topgrade from the desktop, misses npm-installed agents (codex) and drops their shims.
  local npm_bin = npm_global_bin()
  if npm_bin then dirs[#dirs + 1] = npm_bin end
  for _, dir in ipairs({
    require("lib.state")() .. "/bin",
    HOME .. "/.local/bin",
    HOME .. "/.cargo/bin",
    HOME .. "/go/bin",
    HOME .. "/.tmuxifier/bin",
    HOME .. "/.config/hypr/scripts",
  }) do
    dirs[#dirs + 1] = dir
  end
  for dir in (os.getenv("PATH") or ""):gmatch("[^:]+") do
    dirs[#dirs + 1] = dir
  end
  for _, dir in ipairs({ "/usr/local/bin", "/usr/bin", "/bin" }) do
    dirs[#dirs + 1] = dir
  end
  local seen, out = {}, {}
  for _, dir in ipairs(dirs) do
    if not seen[dir] then
      seen[dir] = true
      out[#out + 1] = dir
    end
  end
  return table.concat(out, ":")
end

-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Environment-variables/
local env = {
  PATH = build_path(),
  GTK_THEME = "Breeze-Dark",
  XCURSOR_THEME = Config.cursor.theme,
  XCURSOR_SIZE = tostring(Config.cursor.size),
  QT_QPA_PLATFORMTHEME = "qt6ct", -- for Qt apps
  QT_QPA_PLATFORM = "wayland;xcb",
  QT_AUTO_SCREEN_SCALE_FACTOR = 1,
  HYPRCURSOR_THEME = Config.cursor.hypr_theme,
  HYPRCURSOR_SIZE = tostring(Config.cursor.size),
  XDG_CURRENT_DESKTOP = "Hyprland",
  XDG_SESSION_TYPE = "wayland",
  XDG_SESSION_DESKTOP = "Hyprland",
  TERMINAL = Config.app.term,
}
if Config.drm_devices then env.AQ_DRM_DEVICES = Config.drm_devices end

-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Environment-variables/#nvidia-specific
local nvidia_env = {
  __GL_GSYNC_ALLOWED = "1",
  __GL_VRR_ALLOWED = "0",
}

local offload_env = {
  GBM_BACKEND = Config.nvidia.backend,
  __GLX_VENDOR_LIBRARY_NAME = "nvidia",
  LIBVA_DRIVER_NAME = "nvidia",
  __VK_LAYER_NV_optimus = "NVIDIA_only",
  __NV_PRIME_RENDER_OFFLOAD = "1",
}

--- Registers all environment variables; nvidia_env is added when NVIDIA is enabled, offload_env when not hybrid.
local function init()
  set_env(env)
  if Config.nvidia.enable then
    set_env(nvidia_env)
    if not Config.nvidia.hybrid then set_env(offload_env) end
  end
end

init()
