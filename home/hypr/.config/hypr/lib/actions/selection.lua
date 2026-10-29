--- The multi-selection of the submaps that act on windows (Submap.define `targets`: Windows, Resize, Move). It lives in
--- this module, not in a submap file, so every action that reads or changes it sees the same selection across key
--- presses and across those submaps. Quickshell draws it (the submap_hints `selection` call), so a change is sent there.
local Act = require("lib.act") ---@class ActionLib
local Json = require("lib.json") ---@class Json

--- Selected addresses in the order they were selected, so actions and Quickshell's marks follow that order.
--- @type string[]
local SELECTED = {}
-- Counts every send: each is its own qs-ipc process, and two sent close together can land out of order.
local serial = 0

--- Return address of the currently focused window, or nil.
local function get_active_address()
  local w = hl.get_active_window()

  return w and w.address or nil
end

--- @param addr string
--- @return integer|nil
local function index_of(addr)
  for index, selected in ipairs(SELECTED) do
    if selected == addr then return index end
  end
  return nil
end

--- Send the selection to Quickshell.
local function send()
  serial = serial + 1
  local windows = Json.array()
  for index, addr in ipairs(SELECTED) do
    windows[index] = addr
  end
  Act.Ipc("submap_hints", "selection", Json.encode({ serial = serial, windows = windows }))()
end

--- Tell Quickshell to reread window positions: a relative move or resize raises no Hyprland event of its own.
local function announce_geometry() hl.dispatch(hl.dsp.event("window_targets")) end

--- Forget selected windows that no longer exist: focusing a closed window's address fails, and the action that follows
--- would then hit whatever is focused instead.
local function drop_closed()
  local open = {}
  for _, w in ipairs(hl.get_windows() or {}) do
    open[w.address] = true
  end
  local kept = {}
  for _, addr in ipairs(SELECTED) do
    if open[addr] then kept[#kept + 1] = addr end
  end
  if #kept == #SELECTED then return end
  SELECTED = kept
  send()
end

--- @class Selection
local Selection = {}

--- Toggle select on the focused window.
function Selection.toggle()
  local addr = get_active_address()
  if not addr then return end

  local index = index_of(addr)
  if index then
    table.remove(SELECTED, index)
  else
    SELECTED[#SELECTED + 1] = addr
  end
  send()
end

--- Deselect every window. Sends only when something was selected, as Submap.define calls this on every switch that
--- leaves the `targets` submaps.
function Selection.clear()
  if #SELECTED == 0 then return end
  SELECTED = {}
  send()
end

--- Swap the focused window with the one selected window, then clear the selection.
function Selection.swap()
  drop_closed()
  local active = get_active_address()
  local target, count = nil, 0
  for _, addr in ipairs(SELECTED) do
    if addr ~= active then
      target, count = addr, count + 1
    end
  end
  if not active or count ~= 1 then
    hl.notification.create({ text = "Swap needs exactly one selected window", timeout = 2000 })
    return
  end

  hl.dispatch(hl.dsp.window.swap({ target = "address:" .. target }))
  Selection.clear()
end

--- Wrap fn so it applies to all selected windows.
--- If no SELECTED, runs fn() on the focused window as normal.
--- Restores focus to the original window after iterating.
--- @param fn fun()
--- @return fun()
function Selection.for_selected(fn)
  return function()
    drop_closed()
    if #SELECTED == 0 then
      fn()
      announce_geometry()
      return
    end

    local original = get_active_address()
    for _, addr in ipairs(SELECTED) do
      hl.dispatch(hl.dsp.focus({ window = "address:" .. addr }))
      fn()
    end
    if original then hl.dispatch(hl.dsp.focus({ window = "address:" .. original })) end
    announce_geometry()
  end
end

return Selection
