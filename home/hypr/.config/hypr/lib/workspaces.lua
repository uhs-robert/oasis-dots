-- home/hypr/.config/hypr/lib/workspaces.lua

local Config = require("config") ---@class Config
local ORDER = Config.monitors

--- @class Workspaces
local Workspaces = {}

--- True when `mon` is the monitor a profile entry describes.
--- @param mon HL.Monitor
--- @param entry { description?: string, name?: string, id?: integer }
--- @return boolean
function Workspaces.matches(mon, entry)
  if entry.description and mon.description == entry.description then return true end
  if entry.name and mon.name == entry.name then return true end
  if entry.id and mon.id == entry.id then return true end
  return false
end

--- Assigns every monitor a slot: profile position when matched, else the lowest slot no matched monitor holds.
--- @param monitors HL.Monitor[]
--- @param order table[] Profile entries
--- @return table<string, integer> slots Monitor name to slot
--- @return table<string, boolean> matched Names of monitors that matched a profile entry
function Workspaces.assign_slots(monitors, order)
  local sorted = {}
  for _, mon in ipairs(monitors) do
    sorted[#sorted + 1] = mon
  end
  table.sort(sorted, function(a, b)
    if a.id ~= b.id then return a.id < b.id end
    return a.name < b.name
  end)

  local slots, matched, taken, unknowns = {}, {}, {}, {}
  for _, mon in ipairs(sorted) do
    local found
    for i, entry in ipairs(order) do
      if not taken[i] and Workspaces.matches(mon, entry) then
        found = i
        break
      end
    end
    if found then
      slots[mon.name], matched[mon.name], taken[found] = found, true, true
    else
      unknowns[#unknowns + 1] = mon
    end
  end

  local next_slot = 1
  for _, mon in ipairs(unknowns) do
    while taken[next_slot] do
      next_slot = next_slot + 1
    end
    slots[mon.name], taken[next_slot] = next_slot, true
  end
  return slots, matched
end

--- Slots of the connected monitors under the current profile.
--- @return table<string, integer> slots
--- @return table<string, boolean> matched
function Workspaces.connected_slots() return Workspaces.assign_slots(hl.get_monitors() or {}, ORDER) end

--- Slot of `mon`, counting it as connected even when it was just removed.
--- @param mon HL.Monitor
--- @return integer
function Workspaces.slot_of(mon)
  local monitors = {}
  local present = false
  for _, m in ipairs(hl.get_monitors() or {}) do
    monitors[#monitors + 1] = m
    if m.name == mon.name then present = true end
  end
  if not present then monitors[#monitors + 1] = mon end
  return (Workspaces.assign_slots(monitors, ORDER))[mon.name]
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

--- Returns the monitor name currently holding slot `slot`.
--- @param slot integer 1-based slot index
--- @return string|nil monitor name, or nil if the slot has no monitor
function Workspaces.get_monitor_for_slot(slot)
  for name, idx in pairs((Workspaces.connected_slots())) do
    if idx == slot then return name end
  end
end

return Workspaces
