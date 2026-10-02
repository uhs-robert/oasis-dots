-- home/hypr/.config/hypr/extensions/auto_launcher/sessions.lua
-- Session registry for the launcher; monitor indices follow Config.monitors order.
-- These are generic defaults; add your own from custom/ (see custom/README.md).

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

--- Window classes of file managers whose class differs from their command.
local GUI_FM_CLASS = {
  nautilus = "org.gnome.Nautilus",
  dolphin = "org.kde.dolphin",
}

--- @type table<string, AppEntry[]>|nil built on first use so Config is fully derived
local registry = nil

--- Terminal entry running `exec` under its own window class, since single-instance terminals share a pid.
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

--- The generic sessions shipped with this config, on monitors 1 and 2.
--- @return table<string, AppEntry[]>
function M.defaults()
  local gui_fm = Config.app.gui_file_manager
  local gui_fm_class = GUI_FM_CLASS[gui_fm] or gui_fm
  local tui_fm = Config.app.tui_file_manager

  return {
    ["🌐 Browsing"] = {
      { monitor = 1, ws = 1, cmd = "firefox --new-window", class = "org.mozilla.firefox" },
      M.term({ monitor = 2, ws = 1, exec = tui_fm, class_suffix = tui_fm }),
    },

    ["🗂 Files"] = {
      { monitor = 1, ws = 1, cmd = gui_fm, class = gui_fm_class },
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
