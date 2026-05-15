-- home/hypr/.config/hypr/config/system/monitors.lua

local Config = require("config") ---@class Config
local PERSISTENT_WS = Config.persistent_workspaces
--- @type { description?: string, name?: string, id?: integer, mode?: string, position?: string, scale?: number, transform?: integer }[]
local MONITOR_ORDER = Config.monitors

--- @param mon HL.Monitor
--- @param entry { description?: string, name?: string, id?: integer }
--- @return boolean
local function is_monitor_match(mon, entry)
  if entry.description and mon.description == entry.description then return true end
  if entry.name and mon.name == entry.name then return true end
  if entry.id and mon.id == entry.id then return true end
  return false
end

--- Returns the 1-based position of `mon` in MONITOR_ORDER, or a fallback beyond the list.
--- @param mon HL.Monitor
--- @return integer
local function get_monitor_order_index(mon)
  for i, entry in ipairs(MONITOR_ORDER) do
    if is_monitor_match(mon, entry) then return i end
  end
  return #MONITOR_ORDER + mon.id + 1
end

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

--- Applies hl.monitor() settings for all MONITOR_ORDER entries that have mode defined.
local function init_monitors()
  local monitors = hl.get_monitors()
  for _, entry in ipairs(MONITOR_ORDER) do
    local output = get_monitor_output(entry, monitors)
    if output and entry.mode then
      hl.monitor({
        output = output,
        mode = entry.mode,
        position = entry.position or "auto",
        scale = tostring(entry.scale or 1),
        transform = entry.transform,
      })
    end
  end
end

--- Assigns persistent workspace rules using MONITOR_ORDER index so ranges stay stable
--- regardless of how many monitors are connected.
local function init_workspaces()
  local monitors = hl.get_monitors()
  for i, entry in ipairs(MONITOR_ORDER) do
    local output = get_monitor_output(entry, monitors)
    if output then
      local start_ws = (i - 1) * PERSISTENT_WS + 1
      local end_ws = i * PERSISTENT_WS
      for n = start_ws, end_ws do
        hl.workspace_rule({ workspace = tostring(n), monitor = output, persistent = true })
      end
    end
  end
end

--- Moves workspaces from a disconnected monitor to the first remaining monitor.
--- @param mon HL.Monitor The monitor that was removed
local function on_monitor_removed(mon)
  local removed_idx = get_monitor_order_index(mon)
  local remaining = hl.get_monitors()
  local fallback = remaining[1]

  if PERSISTENT_WS and fallback and removed_idx <= #MONITOR_ORDER then
    for n = 1, PERSISTENT_WS do
      local ws_id = (removed_idx - 1) * PERSISTENT_WS + n
      hl.dispatch(hl.dsp.workspace.move({ workspace = ws_id, monitor = fallback.name }))
    end
  end

  init_monitors()
  if PERSISTENT_WS then init_workspaces() end
end

--- Focuses the first workspace on each monitor so all start in a clean state.
--- Iterates in reverse so focus lands on ORDER[1] / workspace 1 at the end.
--- Only called at startup, not on hotplug events.
local function init_workspace_focus()
  local monitors = hl.get_monitors()
  for i = #MONITOR_ORDER, 1, -1 do
    local output = get_monitor_output(MONITOR_ORDER[i], monitors)
    if output then hl.dispatch(hl.dsp.focus({ workspace = (i - 1) * PERSISTENT_WS + 1 })) end
  end
end

init_monitors()
if PERSISTENT_WS then init_workspaces() end

-- EVENTS
hl.on("monitor.added", function()
  if PERSISTENT_WS then
    init_workspaces()
    if #hl.get_monitors() >= #MONITOR_ORDER then
      init_monitors()
      init_workspace_focus()
    end
  end
end)
hl.on("monitor.removed", on_monitor_removed)
