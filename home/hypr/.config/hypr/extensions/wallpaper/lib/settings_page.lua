-- home/hypr/.config/hypr/extensions/wallpaper/lib/settings_page.lua
-- Settings state written by the Quickshell Settings page, and the status file written back for it

local Json = require("lib.json") ---@class Json
local state_dir = require("lib.state")

--- @class SettingsPage
--- @field SETTING_KEYS string[] Keys taken from the settings state file
--- @field read fun(): string|nil, table|nil Raw settings state text (nil when no file) and its decoded table (nil when the text is not a JSON object)
--- @field settings fun(state: table, ignored?: fun(msg: string)): table Validated subset of `SETTING_KEYS` found in `state`; `ignored` hears about values dropped
--- @field usable fun(state: table, cfg: table, util: table): table<string, string> SettingsPage whose image can be read, by monitor description
--- @field read_status fun(): table Last status written, or an empty table
--- @field read_status_text fun(): string|nil Status file text as written, nil when absent
--- @field write_status fun(status: table): string Replace the status file atomically; returns the text written
local SettingsPage = {}

SettingsPage.SETTING_KEYS =
  { "rotation", "interval_minutes", "time_of_day_enabled", "seasons_enabled", "weather_enabled", "wallpaper_dir" }

local BOOLEAN_KEYS = { rotation = true, time_of_day_enabled = true, seasons_enabled = true, weather_enabled = true }

--- Opening "<path>/." succeeds only for a directory, which plain Lua cannot test otherwise.
local function directory_path(value)
  if type(value) ~= "string" or value == "" then return nil end
  local path = value:gsub("^~(/?)", function(slash) return (os.getenv("HOME") or "") .. slash end):gsub("(.)/+$", "%1")
  local f = io.open(path .. "/.", "r")
  if not f then return nil end
  f:close()
  return path
end

local function path_of(name) return state_dir() .. "/" .. name end

local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local text = f:read("*a")
  f:close()
  return text
end

function SettingsPage.read()
  local raw = read_file(path_of("wallpaper.json"))
  if not raw then return nil, {} end
  local decoded = Json.decode(raw)
  return raw, type(decoded) == "table" and decoded or nil
end

function SettingsPage.settings(state, ignored)
  local out = {}
  for _, key in ipairs(SettingsPage.SETTING_KEYS) do
    local value = state[key]
    if BOOLEAN_KEYS[key] and type(value) == "boolean" then
      out[key] = value
    elseif key == "interval_minutes" and type(value) == "number" and value > 0 then
      out[key] = value
    elseif key == "wallpaper_dir" and value ~= nil then
      out[key] = directory_path(value)
      if not out[key] and ignored then ignored("wallpaper_dir ignored; not a directory: " .. tostring(value)) end
    end
  end
  return out
end

function SettingsPage.usable(state, cfg, util)
  local out = {}
  if type(state.pins) ~= "table" then return out end
  for description, path in pairs(state.pins) do
    local f = type(path) == "string" and io.open(path, "r")
    if f then
      f:close()
      out[description] = path
    else
      util.log(string.format("Pin for %s ignored; cannot read %s", description, tostring(path)), cfg)
    end
  end
  return out
end

function SettingsPage.read_status_text() return read_file(path_of("wallpaper-status.json")) end

function SettingsPage.read_status()
  local decoded = Json.decode(SettingsPage.read_status_text() or "")
  return type(decoded) == "table" and decoded or {}
end

function SettingsPage.write_status(status)
  local path = path_of("wallpaper-status.json")
  os.execute(string.format("mkdir -p '%s'", state_dir()))
  local tmp = path .. ".tmp"
  local text = Json.encode(status) .. "\n"
  local f = io.open(tmp, "w")
  if not f then return text end
  f:write(text)
  f:close()
  os.rename(tmp, path)
  return text
end

return SettingsPage
