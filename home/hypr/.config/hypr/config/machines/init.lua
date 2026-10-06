local Utils = require("lib.utils") ---@class Utils
local Json = require("lib.json") ---@class Json
local Input = require("config.input")

local Machines = {}

local function deep_copy(value)
  if type(value) ~= "table" then return value end

  local copy = {}
  for key, item in pairs(value) do
    copy[deep_copy(key)] = deep_copy(item)
  end
  return copy
end

local function hostname()
  local name = os.getenv("HOSTNAME")
  if not name or name == "" then
    local file = io.open("/etc/hostname", "r")
    if not file then return nil end
    name = file:read("*l")
    file:close()
  end

  if not name then return nil end
  name = name:match("^%s*(.-)%s*$")
  name = name:match("^[^.]+")
  if not name or not name:match("^[A-Za-z0-9_-]+$") then return nil end

  return name
end

local function module_path(module) return package.searchpath(module, package.path) end

--- Load the optional profile for the current hostname.
--- Missing profiles are intentionally ignored; errors in existing profiles (including
--- syntax errors) propagate.
--- @return table
function Machines.load()
  local name = hostname()
  if not name then return {} end

  local module = "config.machines." .. name
  if not module_path(module) then return {} end

  -- Lua 5.4's require also returns the loader data (the file path), which deep_extend would treat as a second source.
  local profile = require(module)
  if type(profile) ~= "table" then error(module .. " must return a table, got " .. type(profile)) end
  return profile
end

local APP_KEYS = { term = true, editor = true, gui_file_manager = true, tui_file_manager = true }

--- Default-app choices saved by the Settings panel in ~/.local/state/hypr/apps.json.
--- @return table
function Machines.apps_state()
  local base = os.getenv("XDG_STATE_HOME") or ((os.getenv("HOME") or "") .. "/.local/state")
  local path = base .. "/hypr/apps.json"
  local file = io.open(path, "r")
  if not file then return {} end
  local text = file:read("*a")
  file:close()

  local data = Json.decode(text)
  if type(data) ~= "table" or type(data.app) ~= "table" then return {} end
  local app = {}
  for key, value in pairs(data.app) do
    if APP_KEYS[key] and type(value) == "string" and value:match("^[%w._+-]+$") then app[key] = value end
  end

  return app
end

--- Merge shared session values with the current machine profile, then the saved UI state.
--- Machine-profile values win so host-specific hardware can override shared defaults; UI state wins over both.
--- @param shared table|nil
--- @return table
function Machines.merge(shared)
  local merged = deep_copy(shared or {})
  Utils.deep_extend(merged, Machines.load())

  local app = Machines.apps_state()
  if next(app) ~= nil then
    merged.app = merged.app or {}
    Utils.deep_extend(merged.app, app)
    if app.term then merged.app.term_cmd = nil end
  end

  merged.input = merged.input or {}
  Utils.deep_extend(merged.input, Input.state())

  return merged
end

return Machines
