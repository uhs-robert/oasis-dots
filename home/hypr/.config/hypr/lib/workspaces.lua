-- home/hypr/.config/hypr/lib/workspaces.lua

local Config = require("config") ---@class Config
local MIN_WS = Config.persistent_workspaces
local ORDER = Config.monitors

--- @class Workspaces
local Workspaces = {}

--- Returns the ORDER index for the given monitor, falling back to mon.id+1.
--- @param mon HL.Monitor
--- @return integer
local function get_order_idx(mon)
  for i, entry in ipairs(ORDER) do
    if
      (entry.description and mon.description == entry.description)
      or (entry.name and mon.name == entry.name)
      or (entry.id and mon.id == entry.id)
    then
      return i
    end
  end

  return #ORDER + mon.id + 1
end

--- Returns start/end global workspace IDs for the given ORDER index.
--- @param idx integer
--- @return integer, integer
local function ws_range(idx) return (idx - 1) * MIN_WS + 1, idx * MIN_WS end

--- @class MonRange
--- @field lo integer  First workspace ID in the range
--- @field hi integer  Last workspace ID in the range

--- Returns the ws range for the active monitor, or nil if unavailable.
--- @return MonRange|nil
local function active_mon_range()
  if not MIN_WS then return nil end
  local mon = hl.get_active_monitor()
  if not mon then return nil end
  local lo, hi = ws_range(get_order_idx(mon))
  return { lo = lo, hi = hi }
end

--- Wraps ws within [start_ws, end_ws].
--- @param ws integer
--- @param start_ws integer
--- @param end_ws   integer
--- @return integer
local function wrap_ws(ws, start_ws, end_ws)
  if ws > end_ws then return start_ws end
  if ws < start_ws then return end_ws end

  return ws
end

--- Converts a next/prev direction to a +1/-1 step.
--- @param dir "next"|"prev"
--- @return integer
local function to_step(dir) return dir == "next" and 1 or -1 end

--- Returns the global workspace ID for local slot `n` on the active monitor.
--- Uses ORDER index for stable ranges regardless of monitor connection order.
--- When persistent_workspaces is false, `n` is returned as-is (default behaviour).
--- @param n integer Local workspace slot (1-N)
--- @return integer
function Workspaces.get_ws_id(n)
  if not MIN_WS then return n end
  local mon = hl.get_active_monitor()
  if not mon then return n end

  return (get_order_idx(mon) - 1) * MIN_WS + n
end

--- Cycles to the next or previous workspace on the active monitor, wrapping at the boundary.
--- @param dir "next"|"prev"
function Workspaces.cycle_local_ws(dir)
  local range = active_mon_range()
  if not range then return end
  local target = wrap_ws(hl.get_active_workspace().id + to_step(dir), range.lo, range.hi)
  hl.dispatch(hl.dsp.focus({ workspace = target }))
end

--- Moves the active window to the next or previous workspace on the active monitor, wrapping at the boundary.
--- @param dir "next"|"prev"
function Workspaces.move_window_local_ws(dir)
  local range = active_mon_range()
  if not range then return end
  local target = wrap_ws(hl.get_active_workspace().id + to_step(dir), range.lo, range.hi)
  hl.dispatch(hl.dsp.window.move({ workspace = target }))
end

--- Resolves a monitor selector string from an ORDER entry.
--- For id-only entries, does a one-time live lookup at call time.
--- @param entry { description?: string, name?: string, id?: integer }
--- @return string|nil
function Workspaces.get_monitor_selector(entry)
  if entry.description then return "desc:" .. entry.description end
  if entry.name then return entry.name end
  if entry.id then
    for _, mon in ipairs(hl.get_monitors()) do
      if mon.id == entry.id then return mon.name end
    end
  end
end

--- Splits monitors into ORDER-matched slots and unrecognized extras.
--- @param monitors HL.Monitor[]
--- @return table<integer, string>, string[]
local function classify_monitors(monitors)
  local filled = {} --- @type table<integer, string>
  local unknowns = {} --- @type string[]
  for _, mon in ipairs(monitors) do
    local idx = get_order_idx(mon)
    if idx <= #ORDER then
      filled[idx] = mon.name
    else
      table.insert(unknowns, mon.name)
    end
  end
  return filled, unknowns
end

--- Builds an ordered slot list: ORDER positions filled first, unknowns backfilling gaps then appended.
--- @param filled   table<integer, string>
--- @param unknowns string[]
--- @return string[]
local function build_ordered_list(filled, unknowns)
  local slots = {} --- @type string[]
  local u = 1
  for i = 1, #ORDER do
    slots[i] = filled[i] or unknowns[u]
    if not filled[i] then u = u + 1 end
  end
  for i = u, #unknowns do
    table.insert(slots, unknowns[i])
  end
  return slots
end

--- Returns the monitor name currently occupying slot `slot` in ORDER.
--- Known monitors fill their configured slot; unknown connected monitors
--- fill empty slots in insertion order (as reported by hl.get_monitors()).
--- @param slot integer 1-based ORDER slot index
--- @return string|nil monitor name, or nil if the slot has no monitor
function Workspaces.get_monitor_for_slot(slot)
  local filled, unknowns = classify_monitors(hl.get_monitors())
  return build_ordered_list(filled, unknowns)[slot]
end

return Workspaces
