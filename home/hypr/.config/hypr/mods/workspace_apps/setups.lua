-- Workspace app launcher setup definitions.
-- Monitor indices follow Config.monitors order in hyprland.lua:

--- @class AppEntry
--- @field monitor integer 1-based monitor index
--- @field cmd string shell command to launch
--- @field next boolean|nil advance this monitor's workspace counter after launching

local M = {}

--- @param session string tmuxifier session name
--- @param monitor integer|nil monitor index (default: 4 = RIGHT)
--- @return AppEntry
local function tmuxifier(session, monitor)
  return { monitor = monitor or 4, cmd = "kitty -e tmuxifier load-session " .. session, next = true }
end

M.setups = {
  ["🌐 Browsing"] = {
    { monitor = 3, cmd = "firefox --new-window", next = true },
    tmuxifier("config"),
  },

  ["🧱 Client"] = {
    { monitor = 3, cmd = "firefox --new-window", next = true },
    tmuxifier("client-dev"),
    tmuxifier("config", 3),
    { monitor = 1, cmd = "flatpak run eu.betterbird.Betterbird" },
    { monitor = 1, cmd = "slack" },
  },

  ["🛠 Config"] = {
    { monitor = 3, cmd = "firefox --new-window", next = true },
    tmuxifier("config"),
    { monitor = 1, cmd = "flatpak run eu.betterbird.Betterbird" },
  },

  ["🗂 Files"] = {
    { monitor = 3, cmd = "dolphin", next = true },
    { monitor = 4, cmd = "kitty -e yazi", next = true },
  },

  ["🧩 Game Mods"] = {
    { monitor = 2, cmd = "steam", next = true },
    { monitor = 3, cmd = "kitty -d ~/Downloads/ -e yazi", next = true },
    { monitor = 4, cmd = "kitty -d ~/.steam/steam/steamapps/ -e yazi", next = true },
  },

  ["🎮 Game"] = {
    { monitor = 2, cmd = "steam", next = true },
  },

  ["📅 Meeting"] = {
    { monitor = 3, cmd = "firefox --new-window", next = true },
    { monitor = 1, cmd = "firefox --new-window https://calendar.google.com/", next = true },
  },

  ["📊 System Monitor"] = {
    { monitor = 3, cmd = "kitty -e journalctl -f", next = true },
    { monitor = 4, cmd = "kitty -e btop", next = true },
  },

  ["🛡️ System Update"] = {
    { monitor = 2, cmd = "kitty -e sysup", next = true },
    { monitor = 3, cmd = "kitty -e journalctl -f", next = true },
  },

  ["💼 Work"] = {
    { monitor = 3, cmd = "firefox --new-window", next = true },
    tmuxifier("uphill", 3),
    tmuxifier("config"),
    { monitor = 1, cmd = "flatpak run eu.betterbird.Betterbird" },
    { monitor = 1, cmd = "slack" },
  },
}

return M
