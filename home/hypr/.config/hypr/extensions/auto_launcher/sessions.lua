-- home/hypr/.config/hypr/extensions/auto_launcher/sessions.lua
-- Workspace app launcher session definitions.
-- Monitor indices follow Config.monitors order in hyprland.lua:

local Config = require("config") ---@class Config

--- @class AppEntry
--- @field monitor integer 1-based monitor index
--- @field ws integer|nil workspace offset within the monitor (default: 1)
--- @field cmd string shell command to launch
--- @field class string|nil window class for dynamic workspace rule and window adoption (mutually exclusive with title)
--- @field title string|nil window title for dynamic workspace rule and window adoption (mutually exclusive with class)
--- @field size [integer, integer]|nil window size as {w, h} (e.g. {1280, 720})
--- @field pos [integer, integer]|nil window position as {x, y} (e.g. {100, 200})
--- @field delay integer|nil milliseconds to wait before launching

--- @class Sessions
--- @field get_sessions fun(): table<string, AppEntry[]> Returns named session presets

local M = {}

--- @return table<string, AppEntry[]>
function M.get_sessions()
  -- Single-instance terminals share one pid, so windows need a per-launch --class to be
  -- targetable. Must contain the term name for the delete submap's substring match.
  local term = Config.app.term or "kitty"

  --- @param opts { monitor: integer, ws: integer|nil, exec: string, class_suffix: string, size: [integer, integer]|nil, pos: [integer, integer]|nil, delay: integer|nil }
  --- @return AppEntry
  local function term_entry(opts)
    local class = term .. "-" .. opts.class_suffix
    return {
      monitor = opts.monitor,
      ws = opts.ws,
      cmd = "term --class " .. class .. " -e " .. opts.exec,
      class = class,
      size = opts.size,
      pos = opts.pos,
      delay = opts.delay,
    }
  end

  --- @param opts { session: string, monitor: integer|nil, ws: integer|nil }
  --- @return AppEntry
  local function tmuxifier(opts)
    return term_entry({
      monitor = opts.monitor or 3,
      ws = opts.ws or 2,
      exec = "tmuxifier load-session " .. opts.session,
      class_suffix = "tmux-" .. opts.session,
    })
  end

  --- @param opts { monitor: integer|nil, ws: integer|nil }|nil
  --- @return AppEntry
  local function betterbird(opts)
    opts = opts or {}
    return {
      monitor = opts.monitor or 4,
      ws = opts.ws or 1,
      cmd = "betterbird",
      class = "eu.betterbird.Betterbird",
    }
  end

  return {
    ["🌐 Browsing"] = {
      { monitor = 3, ws = 1, cmd = "firefox --new-window", class = "firefox" },
      tmuxifier({ session = "config" }),
    },

    ["🧱 Client"] = {
      betterbird(),
      { monitor = 3, ws = 1, cmd = "firefox --new-window", class = "firefox" },
      tmuxifier({ session = "client-dev" }),
      tmuxifier({ session = "config", ws = 3 }),
      { monitor = 4, ws = 1, cmd = "slack", class = "slack", size = { 1064, 461 } },
    },

    ["🛠 Config"] = {
      betterbird(),
      { monitor = 3, ws = 1, cmd = "firefox --new-window", class = "firefox" },
      tmuxifier({ session = "config" }),
    },

    ["🗂 Files"] = {
      { monitor = 3, ws = 1, cmd = "thunar", class = "thunar" },
      term_entry({ monitor = 4, ws = 1, exec = "yazi", class_suffix = "yazi" }),
    },

    ["🧩 Game Mods"] = {
      { monitor = 2, ws = 1, cmd = "steam", class = "steam" },
      term_entry({
        monitor = 3,
        ws = 1,
        exec = "sh -c 'cd ~/Downloads && exec yazi'",
        class_suffix = "yazi-downloads",
      }),
      term_entry({
        monitor = 4,
        ws = 1,
        exec = "sh -c 'cd ~/.steam/steam/steamapps && exec yazi'",
        class_suffix = "yazi-steamapps",
      }),
    },

    ["🎮 Game"] = {
      { monitor = 2, ws = 1, cmd = "steam", class = "steam" },
    },

    ["📅 Meeting"] = {
      { monitor = 3, ws = 1, cmd = "firefox --new-window", class = "firefox" },
      -- Delayed so the blank window above is already snapshotted out; both match "firefox".
      {
        monitor = 1,
        ws = 1,
        cmd = "firefox --new-window https://calendar.google.com/",
        class = "firefox",
        delay = 2000,
      },
    },

    ["📊 System Monitor"] = {
      term_entry({ monitor = 3, ws = 1, exec = "journalctl -f", class_suffix = "journalctl" }),
      term_entry({ monitor = 4, ws = 1, exec = "btop", class_suffix = "btop" }),
    },

    ["🛡️ System Update"] = {
      term_entry({ monitor = 2, ws = 1, exec = "topgrade", class_suffix = "topgrade" }),
      term_entry({ monitor = 3, ws = 1, exec = "journalctl -f", class_suffix = "journalctl" }),
    },

    ["💼 Work"] = {
      betterbird(),
      { monitor = 2, ws = 1, cmd = "qutebrowser", class = "org.qutebrowser.qutebrowser" },
      { monitor = 3, ws = 1, cmd = "firefox --new-window", class = "firefox" },
      tmuxifier({ session = "uphill" }),
      tmuxifier({ session = "config", ws = 3 }),
      { monitor = 4, ws = 1, cmd = "slack", class = "slack", size = { 1064, 461 }, delay = 5000 },
    },
  }
end

return M
