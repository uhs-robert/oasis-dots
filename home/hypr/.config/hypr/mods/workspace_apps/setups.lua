-- Workspace app launcher setup definitions.
-- Monitor indices follow Config.monitors order in hyprland.lua:

--- @class AppEntry
--- @field monitor integer 1-based monitor index
--- @field ws integer|nil workspace offset within the monitor (default: 1)
--- @field cmd string shell command to launch
--- @field class string|nil window class for dynamic workspace rule (mutually exclusive with title)
--- @field title string|nil window title for dynamic workspace rule (mutually exclusive with class)

local M = {}

--- @param opts { session: string, monitor: integer|nil, ws: integer|nil }
--- @return AppEntry
local function tmuxifier(opts)
  return { monitor = opts.monitor or 4, ws = opts.ws or 1, cmd = "kitty -e tmuxifier load-session " .. opts.session }
end

--- @param opts { monitor: integer|nil, ws: integer|nil }|nil
--- @return AppEntry
local function betterbird(opts)
  opts = opts or {}
  return {
    monitor = opts.monitor or 1,
    ws = opts.ws or 2,
    cmd = "flatpak run eu.betterbird.Betterbird",
    class = "eu.betterbird.Betterbird",
  }
end

M.setups = {
  ["🌐 Browsing"] = {
    { monitor = 3, ws = 1, cmd = "firefox --new-window" },
    tmuxifier({ session = "config" }),
  },

  ["🧱 Client"] = {
    { monitor = 3, ws = 1, cmd = "firefox --new-window" },
    tmuxifier({ session = "client-dev" }),
    tmuxifier({ session = "config", monitor = 3, ws = 2 }),
    betterbird(),
    { monitor = 1, ws = 1, cmd = "slack", class = "Slack" },
  },

  ["🛠 Config"] = {
    { monitor = 3, ws = 1, cmd = "firefox --new-window" },
    tmuxifier({ session = "config" }),
    betterbird(),
  },

  ["🗂 Files"] = {
    { monitor = 3, ws = 1, cmd = "dolphin" },
    { monitor = 4, ws = 1, cmd = "kitty -e yazi" },
  },

  ["🧩 Game Mods"] = {
    { monitor = 2, ws = 1, cmd = "steam" },
    { monitor = 3, ws = 1, cmd = "kitty -d ~/Downloads/ -e yazi" },
    { monitor = 4, ws = 1, cmd = "kitty -d ~/.steam/steam/steamapps/ -e yazi" },
  },

  ["🎮 Game"] = {
    { monitor = 2, ws = 1, cmd = "steam" },
  },

  ["📅 Meeting"] = {
    { monitor = 3, ws = 1, cmd = "firefox --new-window" },
    { monitor = 1, ws = 1, cmd = "firefox --new-window https://calendar.google.com/" },
  },

  ["📊 System Monitor"] = {
    { monitor = 3, ws = 1, cmd = "kitty -e journalctl -f" },
    { monitor = 4, ws = 1, cmd = "kitty -e btop" },
  },

  ["🛡️ System Update"] = {
    { monitor = 2, ws = 1, cmd = "kitty -e sysup" },
    { monitor = 3, ws = 1, cmd = "kitty -e journalctl -f" },
  },

  ["💼 Work"] = {
    { monitor = 3, ws = 1, cmd = "firefox --new-window" },
    tmuxifier({ session = "uphill", monitor = 3, ws = 2 }),
    tmuxifier({ session = "config" }),
    betterbird(),
    { monitor = 1, ws = 2, cmd = "slack", class = "Slack" },
    { monitor = 2, ws = 1, cmd = "qutebrowser" },
  },
}

return M
