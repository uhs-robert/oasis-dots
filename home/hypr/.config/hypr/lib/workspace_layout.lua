--- Which monitor owns each numbered workspace in persistent mode.
---
--- The ids form one grid: slot k owns (k-1)*per_monitor+1 .. k*per_monitor. With one monitor connected, that monitor
--- owns 1..single_monitor instead, so with the defaults (5 and 10) undocking hands it the ranges of slots 1 and 2 and
--- no workspace changes number. A workspace that no connected monitor owns parks on the lowest connected slot and
--- goes home when its monitor returns.

local Json = require("lib.json") ---@class Json
local State = require("lib.state")

local Layout = {}

-- The number keys reach ten workspaces per monitor.
Layout.MAX = 10

local function count_in_range(v)
  local whole = type(v) == "number" and math.tointeger(v)
  if whole and whole >= 1 and whole <= Layout.MAX then return whole end
end

--- The Settings panel's counts from workspaces.json, validated; a missing or malformed file yields none.
--- @return { per_monitor?: integer, single_monitor?: integer }
function Layout.state()
  local file = io.open(State() .. "/workspaces.json", "r")
  if not file then return {} end
  local text = file:read("*a")
  file:close()
  local ok, data = pcall(Json.decode, text)
  if not ok or type(data) ~= "table" then return {} end
  return { per_monitor = count_in_range(data.per_monitor), single_monitor = count_in_range(data.single_monitor) }
end

--- Lets the saved counts win over the profile's; `persistent_workspaces = false` (global workspaces) stays off.
--- @param cfg table
function Layout.apply_state(cfg)
  local saved = Layout.state()
  if cfg.persistent_workspaces and saved.per_monitor then cfg.persistent_workspaces = saved.per_monitor end
  if saved.single_monitor then cfg.single_monitor_workspaces = saved.single_monitor end
  cfg.ws_per_monitor = type(cfg.persistent_workspaces) == "number" and cfg.persistent_workspaces or 5
end

--- @param cfg table
--- @param connected integer Number of connected monitors
--- @return boolean
function Layout.is_single(cfg, connected) return connected == 1 and cfg.single_monitor_workspaces ~= nil end

--- First and last workspace a slot owns.
--- @param cfg table
--- @param slot integer
--- @param connected integer Number of connected monitors
--- @return integer, integer
function Layout.range(cfg, slot, connected)
  if Layout.is_single(cfg, connected) then return 1, cfg.single_monitor_workspaces end
  local per = cfg.ws_per_monitor
  return (slot - 1) * per + 1, slot * per
end

--- Owner of every workspace in a connected monitor's range.
--- @param cfg table
--- @param slots table<string, integer> Connected monitor name to slot
--- @return table<integer, string> owners Workspace id to monitor name
function Layout.owners(cfg, slots)
  local connected = 0
  for _ in pairs(slots) do
    connected = connected + 1
  end
  local owners = {}
  for name, slot in pairs(slots) do
    local first, last = Layout.range(cfg, slot, connected)
    for n = first, last do
      owners[n] = name
    end
  end
  return owners
end

--- The moves that put every numbered workspace on its owner, or parked on the lowest connected slot.
--- @param cfg table
--- @param slots table<string, integer> Connected monitor name to slot
--- @param workspaces { id: integer|nil, monitor: string|nil, special: boolean|nil }[]
--- @return { id: integer, monitor: string }[] moves Sorted by id
function Layout.plan(cfg, slots, workspaces)
  local owners = Layout.owners(cfg, slots)
  local park, park_slot
  for name, slot in pairs(slots) do
    if not park_slot or slot < park_slot then
      park, park_slot = name, slot
    end
  end
  if not park then return {} end

  local moves = {}
  for _, ws in ipairs(workspaces) do
    if ws.id and ws.id >= 1 and not ws.special then
      local target = owners[ws.id] or park
      if ws.monitor ~= target then moves[#moves + 1] = { id = ws.id, monitor = target } end
    end
  end
  table.sort(moves, function(a, b) return a.id < b.id end)
  return moves
end

return Layout
