-- home/hypr/.config/hypr/extensions/auto_launcher/sessions.lua
-- Workspace app launcher session registry.
-- Monitor indices follow Config.monitors order in hyprland.lua.
--
-- The sessions here are generic defaults. Add your own from custom/ (see custom/README.md):
--
--   local Sessions = require("extensions.auto_launcher.sessions")
--   Sessions.add("💼 Work", { Sessions.term({ monitor = 1, exec = "btop", class_suffix = "btop" }) })

local Config = require("config") ---@class Config
local Apps = require("lib.actions.apps") ---@class Apps

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
local M = {}

--- @type table<string, AppEntry[]>|nil built on first use so Config is fully derived
local registry = nil

--- Terminal entry: runs `exec` in the configured terminal under a per-launch window class.
--- Single-instance terminals share one pid, so windows need their own --class to be targetable.
--- The class must contain the terminal name for the delete submap's substring match.
--- @param opts { monitor: integer, ws: integer|nil, exec: string, class_suffix: string, size: [integer, integer]|nil, pos: [integer, integer]|nil, delay: integer|nil }
--- @return AppEntry
function M.term(opts)
  local class = (Config.app.term or "kitty") .. "-" .. opts.class_suffix
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

--- Terminal entry that loads a tmuxifier session.
--- @param opts { session: string, monitor: integer|nil, ws: integer|nil }
--- @return AppEntry
function M.tmuxifier(opts)
  return M.term({
    monitor = opts.monitor or 1,
    ws = opts.ws or 2,
    exec = "tmuxifier load-session " .. opts.session,
    class_suffix = "tmux-" .. opts.session,
  })
end

--- The sessions shipped with this config. Each sits on monitor 1 and 2 and only uses what the
--- installer provides, so it works on any machine; the launcher folds missing monitors onto the last one.
--- @return table<string, AppEntry[]>
function M.defaults()
  local gui_fm = Config.app.gui_file_manager
  local tui_fm = Config.app.tui_file_manager

  return {
    ["🌐 Browsing"] = {
      { monitor = 1, ws = 1, cmd = "firefox --new-window", class = "org.mozilla.firefox" },
      M.term({ monitor = 2, ws = 1, exec = tui_fm, class_suffix = tui_fm }),
    },

    ["🗂 Files"] = {
      { monitor = 1, ws = 1, cmd = gui_fm, class = gui_fm },
      M.term({ monitor = 2, ws = 1, exec = tui_fm, class_suffix = tui_fm }),
    },

    ["🎮 Game"] = {
      { monitor = 1, ws = 1, cmd = Apps.map.steam.cmd, class = "steam" },
    },

    ["📊 System Monitor"] = {
      M.term({ monitor = 1, ws = 1, exec = "journalctl -f", class_suffix = "journalctl" }),
      M.term({ monitor = 2, ws = 1, exec = "btop", class_suffix = "btop" }),
    },

    ["🛡️ System Update"] = {
      M.term({ monitor = 1, ws = 1, exec = "topgrade", class_suffix = "topgrade" }),
      M.term({ monitor = 2, ws = 1, exec = "journalctl -f", class_suffix = "journalctl" }),
    },
  }
end

--- @return table<string, AppEntry[]>
local function sessions()
  if not registry then registry = M.defaults() end
  return registry
end

--- Adds a session, replacing any existing one of the same name.
--- @param name string label shown in the picker
--- @param apps AppEntry[]
function M.add(name, apps) sessions()[name] = apps end

--- Removes a session by name; a missing name is ignored.
--- @param name string
function M.remove(name) sessions()[name] = nil end

--- Drops every session, defaults included, for configs that want only their own.
function M.clear() registry = {} end

--- The current sessions, keyed by picker label.
--- @return table<string, AppEntry[]>
function M.get_sessions() return sessions() end

return M
