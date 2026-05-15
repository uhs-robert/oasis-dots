-- home/hypr/.config/hypr/lib/workspaces.lua

local Config = require("config") ---@class Config
local MIN_WS = Config.persistent_workspaces
local ORDER = Config.monitors

--- @class Workspaces
local WORKSPACES = {}

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

--- Returns the global workspace ID for local slot `n` on the active monitor.
--- Uses ORDER index for stable ranges regardless of monitor connection order.
--- When persistent_workspaces is false, `n` is returned as-is (default behaviour).
--- @param n integer Local workspace slot (1-N)
--- @return integer
function WORKSPACES.get_ws_id(n)
  if not MIN_WS then return n end
  local mon = hl.get_active_monitor()
  if not mon then return n end
  return (get_order_idx(mon) - 1) * MIN_WS + n
end

--- Cycles to the next or previous workspace on the active monitor, wrapping at the boundary.
--- @param dir "next"|"prev"
function WORKSPACES.cycle_local_ws(dir)
  if not MIN_WS then return end
  local mon = hl.get_active_monitor()
  if not mon then return end
  local start_ws, end_ws = ws_range(get_order_idx(mon))
  local next_ws = hl.get_active_workspace().id + (dir == "next" and 1 or -1)
  if next_ws > end_ws then next_ws = start_ws end
  if next_ws < start_ws then next_ws = end_ws end
  hl.dispatch(hl.dsp.focus({ workspace = next_ws }))
end

--- Moves the active window to the next or previous workspace on the active monitor.
--- Clamped at the monitor's boundary so the window stays on the same monitor.
--- @param dir "next"|"prev"
function WORKSPACES.move_window_local_ws(dir)
  if not MIN_WS then return end
  local mon = hl.get_active_monitor()
  if not mon then return end
  local start_ws, end_ws = ws_range(get_order_idx(mon))
  local target = hl.get_active_workspace().id + (dir == "next" and 1 or -1)
  if target > end_ws then target = start_ws end
  if target < start_ws then target = end_ws end
  hl.dispatch(hl.dsp.window.move({ workspace = target }))
end

--- Resolves a monitor selector string from an ORDER entry.
--- For id-only entries, does a one-time live lookup at call time.
--- @param entry { description?: string, name?: string, id?: integer }
--- @return string|nil
function WORKSPACES.get_monitor_selector(entry)
  if entry.description then return "desc:" .. entry.description end
  if entry.name then return entry.name end
  if entry.id then
    for _, mon in ipairs(hl.get_monitors()) do
      if mon.id == entry.id then return mon.name end
    end
  end
end

return WORKSPACES
