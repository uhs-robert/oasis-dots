-- home/hypr/.config/hypr/lib/workspaces.lua

local Config = require("config") ---@class Config
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
