local Config = require("config") ---@class Config
local Json = require("lib.json") ---@class Json
local Workspaces = require("lib.workspaces") ---@class Workspaces
local Layout = require("lib.workspace_layout")
local SessionStart = require("lib.session_start")
--- @type { description?: string, name?: string, id?: integer, mode?: string, position?: string, scale?: number, transform?: integer, primary?: boolean, start_delay_ms?: integer }[]
local MONITOR_ORDER = Config.monitors

local is_monitor_match = Workspaces.matches

-- Hyprland 0.57 aborts when a dock monitor comes up with no working mode in the first second after login
-- (hyprwm/Hyprland#16727). A disabled monitor is skipped there, so entries with `start_delay_ms` stay off until the
-- dock settles. Only the first config load of a process waits; a later reload enables them at once.

--- A disabled monitor leaves `hl.get_monitors()`, so an id-only entry could never be found again to turn it back on.
--- @param entry { description?: string, name?: string, start_delay_ms?: integer }
--- @return boolean
local function delays_start(entry) return entry.start_delay_ms ~= nil and (entry.description or entry.name) ~= nil end

local start_delay_ms, has_undelayed_entry = 0, false
if not SessionStart.started() then
  for _, entry in ipairs(MONITOR_ORDER) do
    if delays_start(entry) then
      start_delay_ms = math.max(start_delay_ms, entry.start_delay_ms)
    else
      has_undelayed_entry = true
    end
  end
end
-- Hyprland applies monitor rules on a monitor's render, so with every monitor held the release would never land.
local holding_late_monitors = start_delay_ms > 0 and has_undelayed_entry
local released_late_monitors = false

--- Resolves the `output` selector for hl.monitor() from an order entry.
--- Falls back to a live monitor lookup when only `id` is provided.
--- @param entry { description?: string, name?: string, id?: integer }
--- @param monitors table[] Live monitor list for id-based lookup
--- @return string|nil
local function get_monitor_output(entry, monitors)
  if entry.description then return "desc:" .. entry.description end
  if entry.name then return entry.name end
  if entry.id then
    for _, mon in ipairs(monitors) do
      if mon.id == entry.id then return mon.name end
    end
  end
end

--- Reads the UI-written per-monitor overrides keyed by description or connector name.
--- A missing, unreadable or malformed file yields no overrides.
--- @return table<string, table>
local function load_state()
  local base = os.getenv("XDG_STATE_HOME")
  if not base or base == "" then base = (os.getenv("HOME") or "") .. "/.local/state" end
  local file = io.open(base .. "/hypr/monitors.json", "r")
  if not file then return {} end
  local text = file:read("*a")
  file:close()
  local data = Json.decode(text)
  if type(data) ~= "table" or type(data.monitors) ~= "table" then return {} end
  return data.monitors
end

--- Finds the override for a profile entry under its own or its live monitor's description, then connector.
--- @param state table<string, table>
--- @param entry { description?: string, name?: string, id?: integer }
--- @param monitors table[]
--- @return table|nil
local function state_for(state, entry, monitors)
  local keys = { entry.description, entry.name }
  for _, mon in ipairs(monitors) do
    if is_monitor_match(mon, entry) then
      keys = { entry.description, mon.description, entry.name, mon.name }
      break
    end
  end
  for i = 1, 4 do
    local key = keys[i]
    if key and type(state[key]) == "table" then return state[key] end
  end
end

--- Applies one monitor rule; a state override replaces only the fields it carries.
--- @param output string
--- @param base table
--- @param override table|nil
--- @param enable boolean|nil send `disabled = false`: hl.monitor() keeps the fields a new rule leaves out
local function apply_rule(output, base, override, enable)
  local rule = {
    output = output,
    mode = base.mode,
    position = base.position or "auto",
    scale = tostring(base.scale or 1),
    transform = base.transform,
  }
  if override then
    if type(override.mode) == "string" then rule.mode = override.mode end
    if type(override.position) == "string" then rule.position = override.position end
    if override.scale ~= nil then rule.scale = tostring(override.scale) end
    if type(override.transform) == "number" then rule.transform = override.transform end
    if override.disabled == true then rule = { output = output, disabled = true } end
  end
  if enable and not rule.disabled then rule.disabled = false end
  if rule.disabled ~= nil or rule.mode then hl.monitor(rule) end
end

--- Applies hl.monitor() settings for MONITOR_ORDER entries, then UI overrides on top.
--- Unknown monitors (not in MONITOR_ORDER) get preferred mode/auto position/scale 1
--- so a newly plugged-in display still comes up usable instead of unconfigured.
local function init_monitors()
  local monitors = hl.get_monitors()
  local state = load_state()
  local handled = {}
  for _, entry in ipairs(MONITOR_ORDER) do
    local output = get_monitor_output(entry, monitors)
    local override = state_for(state, entry, monitors)
    local delayed = delays_start(entry)
    if holding_late_monitors and delayed then override = { disabled = true } end
    if output then apply_rule(output, entry, override, released_late_monitors and delayed) end
    if entry.description then handled[entry.description] = true end
    if entry.name then handled[entry.name] = true end
  end

  for _, mon in ipairs(monitors) do
    local known = false
    for _, entry in ipairs(MONITOR_ORDER) do
      if is_monitor_match(mon, entry) then
        known = true
        break
      end
    end
    if not known then
      local key = state[mon.description] and mon.description or mon.name
      local output = key == mon.description and "desc:" .. key or mon.name
      apply_rule(
        output,
        { mode = "preferred", position = "auto", scale = 1 },
        state_for(state, { description = mon.description, name = mon.name }, monitors)
      )
      handled[key] = true
    end
  end

  -- Overrides for monitors that are unplugged or disabled (so absent from the live list).
  for key, override in pairs(state) do
    if not handled[key] and type(override) == "table" and override.disabled == true then
      apply_rule(override.description == true and "desc:" .. key or key, {}, override)
    end
  end
end

local persistent_rules = {} --- @type table<integer, { output: string, rule: HL.WorkspaceRule }>

--- Connected monitors and their slots, leaving out one that is being removed.
--- @param removed? HL.Monitor
--- @return HL.Monitor[] monitors
--- @return table<string, integer> slots
local function connected_monitors(removed)
  local monitors = {}
  for _, mon in ipairs(hl.get_monitors()) do
    if not removed or mon.name ~= removed.name then monitors[#monitors + 1] = mon end
  end
  return monitors, (Workspaces.assign_slots(monitors, MONITOR_ORDER))
end

--- Pins every connected monitor's range to it and disables rules left over from an earlier assignment.
--- @param slots table<string, integer>
local function pin_workspaces(slots)
  local wanted = Layout.owners(Config, slots)
  for n, held in pairs(persistent_rules) do
    if wanted[n] ~= held.output then
      held.rule:set_enabled(false)
      persistent_rules[n] = nil
    end
  end
  for n, output in pairs(wanted) do
    if not persistent_rules[n] then
      local rule = hl.workspace_rule({ workspace = tostring(n), monitor = output, persistent = true })
      persistent_rules[n] = { output = output, rule = rule }
    end
  end
end

--- Moves each numbered workspace to its owner, or parks it, and keeps the focused one focused.
--- @param slots table<string, integer>
--- @return boolean followed True when the focused workspace moved and focus went with it
local function move_workspaces(slots)
  local live = {}
  for _, ws in ipairs(hl.get_workspaces()) do
    live[#live + 1] = { id = ws.id, special = ws.special, monitor = ws.monitor and ws.monitor.name }
  end
  local active = hl.get_active_workspace()
  local active_id = active and not active.special and active.id
  local followed = false
  for _, move in ipairs(Layout.plan(Config, slots, live)) do
    hl.dispatch(hl.dsp.workspace.move({ workspace = move.id, monitor = move.monitor }))
    if move.id == active_id then followed = true end
  end
  if followed then hl.dispatch(hl.dsp.focus({ workspace = active_id })) end
  return followed
end

--- Sets the X primary output to whichever MONITOR_ORDER entry has `primary = true`, if connected.
--- xrandr's primary flag isn't exposed via hl.monitor(), so this shells out directly.
local function set_primary_monitor()
  local monitors = hl.get_monitors()
  for _, entry in ipairs(MONITOR_ORDER) do
    if entry.primary then
      for _, mon in ipairs(monitors) do
        if is_monitor_match(mon, entry) then
          hl.exec_cmd("xrandr --output " .. mon.name .. " --primary")
          return
        end
      end
    end
  end
end

--- Applies monitor settings, then pins and moves the persistent workspaces for the monitors now connected.
--- @param added? HL.Monitor A monitor just plugged in, which gets focus on its first workspace
--- @param removed? HL.Monitor A monitor just unplugged
local function apply_layout(added, removed)
  init_monitors()
  set_primary_monitor()
  if not Config.persistent_workspaces then return end
  local monitors, slots = connected_monitors(removed)
  if #monitors == 0 then return end
  pin_workspaces(slots)
  local followed = move_workspaces(slots)
  if added and slots[added.name] and not followed then
    hl.dispatch(hl.dsp.focus({ workspace = (Layout.range(Config, slots[added.name], #monitors)) }))
  end
end

--- @class Monitors
local Monitors = {}

--- Returns `slot` when a connected monitor holds it, else the highest connected slot.
--- @param slot integer 1-based slot index
--- @return integer
function Monitors.resolve_slot(slot)
  local highest
  for _, idx in pairs((Workspaces.connected_slots())) do
    if idx == slot then return slot end
    if not highest or idx > highest then highest = idx end
  end
  return highest or slot
end

--- True when one monitor is connected and owns the single-monitor range.
--- @return boolean
function Monitors.is_single() return Layout.is_single(Config, #hl.get_monitors()) end

--- Re-reads the saved workspace counts and re-lays the workspaces; Settings > Style calls this through `hyprctl eval`.
function Monitors.apply()
  Layout.apply_state(Config)
  apply_layout()
end

local function init()
  if holding_late_monitors then
    hl.timer(function()
      holding_late_monitors = false
      released_late_monitors = true
      apply_layout()
    end, { timeout = start_delay_ms, type = "oneshot" })
  end
  apply_layout()
  hl.on("hyprland.start", function() apply_layout() end)
  hl.on("monitor.added", function(mon) apply_layout(mon) end)
  hl.on("monitor.removed", function(mon) apply_layout(nil, mon) end)
end

init()

return Monitors
