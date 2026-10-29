--- The multi-selection of the submaps that act on windows (Submap.define `targets`: Windows, Resize, Move). It lives in
--- this module, not in a submap file, so every action that reads or changes it sees the same selection across key
--- presses and across those submaps. A selected window gets a thick border in the theme's secondary colour, and
--- Quickshell numbers it (the submap_hints `selection` call), so a change is sent there.
local Act = require("lib.act") ---@class ActionLib
local Json = require("lib.json") ---@class Json

-- Tags kept on the windows themselves, as a reload keeps their border overrides but starts this module afresh.
-- SELECTED_TAG marks a window wearing the selection border; PINNED_TAG one whose colours were put back by hand.
local SELECTED_TAG = "targets_selected"
local PINNED_TAG = "targets_border_pinned"

--- Selected addresses in the order they were selected, so actions and Quickshell's numbers follow that order.
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

--- @param window table
--- @param tag string
--- @return boolean
local function has_tag(window, tag)
  local tags = window.tags
  if type(tags) ~= "table" then return tostring(tags or ""):find(tag, 1, true) ~= nil end
  for _, each in pairs(tags) do
    if tostring(each):find(tag, 1, true) then return true end
  end
  return false
end

--- @param addr string
--- @param prop string
--- @param value string
local function set_prop(addr, prop, value)
  hl.dispatch(hl.dsp.window.set_prop({ window = "address:" .. addr, prop = prop, value = value }))
end

--- @param addr string
--- @param tag string
--- @param on boolean
local function tag_window(addr, tag, on)
  hl.dispatch(hl.dsp.window.tag({ window = "address:" .. addr, tag = (on and "+" or "-") .. tag }))
end

--- A border colour from the config (a gradient table, or a plain value) as a `set_prop` value. Hyprland 0.57's
--- set_prop silently drops a value it cannot read: "0xAARRGGBB" (how the config hands colours back) beside an angle,
--- and an angle after a single colour. So each colour becomes "rgba(RRGGBBAA)" and only a real gradient gets its angle.
--- @param value any
--- @return string
local function gradient_text(value)
  if type(value) ~= "table" then return tostring(value) end
  local parts = {}
  for _, colour in ipairs(value.colors or {}) do
    local alpha, rgb = tostring(colour):match("^0[xX](%x%x)(%x%x%x%x%x%x)$")
    parts[#parts + 1] = alpha and ("rgba(" .. rgb:lower() .. alpha:lower() .. ")") or tostring(colour)
  end
  if #parts > 1 then parts[#parts + 1] = tostring(math.floor((value.angle or 0) + 0.5)) .. "deg" end
  return table.concat(parts, " ")
end

--- The theme's secondary colour as Hyprland reads it; the palette holds "#rrggbb".
--- @return string
local function selection_colour()
  local ok, Theme = pcall(require, "theme")
  local hex = ok and Theme.colors and Theme.colors.theme_secondary or "#F0E68C"
  return "rgba(" .. hex:gsub("^#", ""):lower() .. "ff)"
end

--- Give a window the selection border: twice the configured width, in the secondary colour.
--- @param addr string
local function mark(addr)
  local width = tonumber(hl.get_config("general.border_size")) or 2
  local colour = selection_colour()
  set_prop(addr, "border_size", tostring(math.max(2, 2 * width)))
  set_prop(addr, "active_border_color", colour)
  set_prop(addr, "inactive_border_color", colour)
  tag_window(addr, SELECTED_TAG, true)
end

--- Take the selection border off a window. The width override can be unset; a colour override cannot (Hyprland 0.57
--- ignores "unset" for it), so the colours are set to the configured ones and the window is tagged to follow them when
--- they change (see Selection.follow_config).
--- @param addr string
local function unmark(addr)
  set_prop(addr, "border_size", "unset")
  set_prop(addr, "active_border_color", gradient_text(hl.get_config("general.col.active_border")))
  set_prop(addr, "inactive_border_color", gradient_text(hl.get_config("general.col.inactive_border")))
  tag_window(addr, SELECTED_TAG, false)
  tag_window(addr, PINNED_TAG, true)
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
    unmark(addr)
  else
    SELECTED[#SELECTED + 1] = addr
    mark(addr)
  end
  send()
end

--- Deselect every window. Sends only when something was selected, as Submap.define calls this on every switch that
--- leaves the `targets` submaps.
function Selection.clear()
  if #SELECTED == 0 then return end
  for _, addr in ipairs(SELECTED) do
    unmark(addr)
  end
  SELECTED = {}
  send()
end

--- Keep the borders in step with the config, on every config change (a reload, or the screen frame setting widths and
--- colours): a window still selected gets its border again at the new width, one tagged selected by a Lua state a
--- reload replaced loses it, and a pinned one takes the new colours. Hooked once per config load by Submap.define.
function Selection.follow_config()
  hl.on("config.props_refreshed", function()
    for _, window in ipairs(hl.get_windows() or {}) do
      if index_of(window.address) then
        mark(window.address)
      elseif has_tag(window, SELECTED_TAG) or has_tag(window, PINNED_TAG) then
        unmark(window.address)
      end
    end
  end)
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
