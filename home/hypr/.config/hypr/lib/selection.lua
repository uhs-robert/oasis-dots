--- The multi-selection of the submaps that act on windows (Submap.define `targets`: Windows, Resize, Move). It lives in
--- this module, not in a submap file, so every action that reads or changes it sees the same selection across key
--- presses and across those submaps. A selected window gets a thick border in the theme's secondary colour, and
--- Quickshell numbers it (the submap_hints `selection` call), so a change is sent there.
local Act = require("lib.act") ---@class ActionLib
local Json = require("lib.json") ---@class Json

-- Kept on the window itself, as a reload keeps window tags but starts this module afresh. A window rule matching it
-- draws the selection border, so adding or removing the tag is all a selection change does to the border.
local SELECTED_TAG = "targets_selected"
local BORDER_RULE = "targets_selected_border"

--- Selected addresses in the order they were selected, so actions and Quickshell's numbers follow that order.
--- @type string[]
local SELECTED = {}
--- This config load's place among all of them, so Quickshell can order sends across a reload, which restarts `serial`:
--- the system's uptime in centiseconds, which only grows while Hyprland and the bar run. os.time() is the fallback where
--- /proc is missing; it counts seconds, so two reloads within one could share it.
--- @return integer
local function load_generation()
  local file = io.open("/proc/uptime", "r")
  local uptime = file and tonumber((file:read("*l") or ""):match("^(%d+%.?%d*)"))
  if file then file:close() end
  if uptime then return math.floor(uptime * 100) end
  return os.time()
end
local GENERATION = load_generation()
-- Counts every send in this generation: each is its own qs-ipc process, and two sent close together can land out of
-- order, so Quickshell keeps the newest (generation, serial).
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
--- @param tag string
--- @param on boolean
local function tag_window(addr, tag, on)
  hl.dispatch(hl.dsp.window.tag({ window = "address:" .. addr, tag = (on and "+" or "-") .. tag }))
end

--- The theme's secondary colour as Hyprland reads it; the palette holds "#rrggbb".
--- @return string
local function selection_colour()
  local ok, Theme = pcall(require, "theme")
  local hex = ok and Theme.colors and Theme.colors.theme_secondary or "#F0E68C"
  return "rgba(" .. hex:gsub("^#", ""):lower() .. "ff)"
end

-- What the border rule was last registered with, so the config event, which fires on every config change, only
-- touches the rule when its width or colour moved.
local registered_border = nil

--- Register (or, by its name, update) the rule that draws the selection border: twice the configured width, in the
--- secondary colour. Two colours in `border_color` set the active and the inactive border.
local function register_border_rule()
  local configured = hl.get_config("general.border_size")
  local width = math.max(2, 2 * (tonumber(configured) or 2))
  local colour = selection_colour()
  local key = width .. " " .. colour
  if key == registered_border then return end
  registered_border = key
  hl.window_rule({
    name = BORDER_RULE,
    match = { tag = SELECTED_TAG },
    border_color = colour .. " " .. colour,
    border_size = width,
  })
end

--- Send the selection to Quickshell.
local function send()
  serial = serial + 1
  local windows = Json.array()
  for index, addr in ipairs(SELECTED) do
    windows[index] = addr
  end
  Act.Ipc("submap_hints", "selection", Json.encode({ generation = GENERATION, serial = serial, windows = windows }))()
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
    tag_window(addr, SELECTED_TAG, false)
  else
    SELECTED[#SELECTED + 1] = addr
    tag_window(addr, SELECTED_TAG, true)
  end
  send()
end

--- Deselect every window. Sends only when something was selected, as Submap.define calls this on every switch that
--- leaves the `targets` submaps.
function Selection.clear()
  if #SELECTED == 0 then return end
  for _, addr in ipairs(SELECTED) do
    tag_window(addr, SELECTED_TAG, false)
  end
  SELECTED = {}
  send()
end

--- Deselect every window and send the empty selection whatever the bar last heard. Submap.define calls this on coming
--- into the `targets` submaps from outside, so an update the bar missed (a qs-ipc call that failed, a bar restart)
--- cannot outlast the visit.
function Selection.resync()
  for _, addr in ipairs(SELECTED) do
    tag_window(addr, SELECTED_TAG, false)
  end
  SELECTED = {}
  send()
end

--- This config load's generation, which `submap_hints clear` carries so the bar drops any send from an older one.
--- @return integer
function Selection.generation() return GENERATION end

--- Keep the border rule in step with the config, on every config change (a reload, or the screen frame setting widths
--- and colours), and take the tag off a window that a Lua state a reload replaced left selected. Hooked once per config
--- load by Submap.define.
function Selection.follow_config()
  register_border_rule()
  hl.on("config.props_refreshed", function()
    register_border_rule()
    for _, window in ipairs(hl.get_windows() or {}) do
      if has_tag(window, SELECTED_TAG) and not index_of(window.address) then
        tag_window(window.address, SELECTED_TAG, false)
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
