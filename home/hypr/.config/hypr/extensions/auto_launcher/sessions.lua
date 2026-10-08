-- home/hypr/.config/hypr/extensions/auto_launcher/sessions.lua
-- Session registry for the launcher; monitor indices follow Config.monitors order.
-- These are generic defaults; add your own from custom/ (see custom/README.md).
--
-- Saved sessions live in `<lib/state.lua dir>/sessions.json`, written by the Settings Sessions tab and re-read each
-- time the picker opens. They win over a Lua session of the same name and launch sequentially (see Launcher).
--   { "version": 1, "sessions": { "<name>": { "windows": [ <AppEntry as JSON, snake_case fields> ] } } }
-- Entries failing the AppEntry field types, or lacking cmd or monitor/special, are skipped.

local Config = require("config") ---@class Config
local Apps = require("lib.actions.apps") ---@class Apps
local Json = require("lib.json") ---@class Json
local state_dir = require("lib.state")

--- @class AppEntry
--- @field monitor integer|nil 1-based monitor index; required unless `special` is set
--- @field ws integer|nil workspace offset within the monitor (default: 1)
--- @field cmd string shell command to launch
--- @field class string|nil window class for dynamic workspace rule and window adoption (mutually exclusive with title)
--- @field title string|nil window title for dynamic workspace rule and window adoption (mutually exclusive with class)
--- @field size [integer, integer]|nil window size as {w, h} (e.g. {1280, 720})
--- @field pos [integer, integer]|nil window position as {x, y} (e.g. {100, 200})
--- @field delay integer|nil milliseconds to wait before launching
--- @field special string|nil special workspace name without the `special:` prefix; replaces monitor/ws
--- @field float boolean|nil float the window before size/pos are applied
--- @field guessed boolean|nil set by capture when cmd was reconstructed from /proc; ignored by the launcher

--- @class SessionInfo
--- @field apps AppEntry[]
--- @field source "lua"|"saved"
--- @field sequential boolean tiled entries launch one at a time, in order

--- @class Sessions
local M = {}

--- Window classes of file managers whose class differs from their command.
local GUI_FM_CLASS = {
  nautilus = "org.gnome.Nautilus",
  dolphin = "org.kde.dolphin",
}

--- @type table<string, AppEntry[]>|nil built on first use so Config is fully derived
local registry = nil

--- @type table<string, boolean> names of Lua sessions added with `sequential = true`
local sequential_names = {}

--- Accepted type of each AppEntry field; "pair" is a two-number array.
local FIELD_TYPES = {
  class = "string",
  cmd = "string",
  delay = "number",
  float = "boolean",
  guessed = "boolean",
  monitor = "number",
  pos = "pair",
  size = "pair",
  special = "string",
  title = "string",
  ws = "number",
}

--- @param value any
--- @param kind string
--- @return boolean
local function has_type(value, kind)
  if kind == "pair" then return type(value) == "table" and type(value[1]) == "number" and type(value[2]) == "number" end
  return type(value) == kind
end

--- Copies the recognised, correctly typed fields of `raw` into a plain entry.
--- Returns nil when the result could not launch: no cmd, or neither monitor nor special.
--- @param raw any
--- @return AppEntry|nil
function M.sanitize_entry(raw)
  if type(raw) ~= "table" then return nil end
  local entry = {}
  for field, kind in pairs(FIELD_TYPES) do
    if has_type(raw[field], kind) then
      entry[field] = kind == "pair" and { raw[field][1], raw[field][2] } or raw[field]
    end
  end
  if not entry.cmd or not (entry.monitor or entry.special) then return nil end
  return entry
end

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
--- @param opts { sequential: boolean|nil }|nil sequential launches tiled entries one at a time, like saved sessions
function M.add(name, apps, opts)
  sessions()[name] = apps
  sequential_names[name] = opts ~= nil and opts.sequential == true or nil
end

--- Removes a session by name; a missing name is ignored.
--- @param name string
function M.remove(name)
  sessions()[name] = nil
  sequential_names[name] = nil
end

--- Drops every session, defaults included, for configs that want only their own.
function M.clear()
  registry = {}
  sequential_names = {}
end

--- @return string
function M.saved_path() return state_dir() .. "/sessions.json" end

--- Reads the saved sessions file; a missing file yields none and a malformed one warns and yields none.
--- @return table<string, AppEntry[]>
function M.load_saved()
  local file = io.open(M.saved_path(), "r")
  if not file then return {} end
  local text = file:read("a")
  file:close()

  local data = Json.decode(text)
  if type(data) ~= "table" or type(data.sessions) ~= "table" then
    hl.notification.create({ text = "Saved sessions file is malformed: " .. M.saved_path(), timeout = 5000 })
    return {}
  end

  local saved = {}
  for name, session in pairs(data.sessions) do
    if type(session) == "table" and type(session.windows) == "table" then
      local apps = {}
      for _, raw in ipairs(session.windows) do
        apps[#apps + 1] = M.sanitize_entry(raw)
      end
      saved[name] = apps
    end
  end
  return saved
end

--- Every session the picker offers: Lua sessions, then saved ones over them on a name clash.
--- @return table<string, SessionInfo>
function M.resolve()
  local merged = {}
  for name, apps in pairs(sessions()) do
    merged[name] = { apps = apps, source = "lua", sequential = sequential_names[name] == true }
  end
  for name, apps in pairs(M.load_saved()) do
    merged[name] = { apps = apps, source = "saved", sequential = true }
  end
  return merged
end

--- The current sessions, keyed by picker label; a fresh table, saved sessions included.
--- @return table<string, AppEntry[]>
function M.get_sessions()
  local apps_by_name = {}
  for name, info in pairs(M.resolve()) do
    apps_by_name[name] = info.apps
  end
  return apps_by_name
end

--- Writes every session to `out_path` as `{ "sessions": { "<name>": { source, sequential, windows } } }`
--- so Settings can list Lua sessions beside saved ones. Fields that are not plain data are dropped.
--- @param out_path string
function M.export(out_path)
  local exported = {}
  for name, info in pairs(M.resolve()) do
    local windows = {}
    for _, app in ipairs(info.apps) do
      windows[#windows + 1] = M.sanitize_entry(app)
    end
    exported[name] = { source = info.source, sequential = info.sequential, windows = Json.array(windows) }
  end
  local file = assert(io.open(out_path, "w"))
  file:write(Json.encode({ sessions = exported }))
  file:close()
end

return M
