local Utils = require("lib.utils") ---@class Utils

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

  return require(module)
end

--- Merge shared session values with the current machine profile.
--- Machine-profile values win so host-specific hardware can override shared defaults.
--- @param shared table|nil
--- @return table
function Machines.merge(shared)
  local merged = deep_copy(shared or {})
  Utils.deep_extend(merged, Machines.load())

  return merged
end

return Machines
