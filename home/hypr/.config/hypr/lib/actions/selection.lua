--- The Windows submap's multi-selection. It lives in this module, not in the submap file, so every action that reads
--- or changes it sees the same selection across key presses.

--- Selected windows: { [addr] = { active, inactive } }, stores original border colors.
local SELECTED = {}
local SELECTION_COLOR = "rgba(ffaa00ff)"

--- Return address of the currently focused window, or nil.
local function get_active_address()
  local w = hl.get_active_window()

  return w and w.address or nil
end

--- Return the theme's { active, inactive } border colors.
--- TODO: Convert to Tags/Window Rules when https://github.com/hyprwm/Hyprland/discussions/14030 is resolved.
local function get_theme_borders()
  local ok, Theme = pcall(require, "theme")
  local c = ok and Theme.colors or {}

  return { active = c.theme_primary, inactive = c.bg_mantle }
end

--- Override active + inactive border color for a window by address.
local function set_border(addr, active, inactive)
  hl.dispatch(hl.dsp.window.set_prop({ window = "address:" .. addr, prop = "active_border_color", value = active }))
  hl.dispatch(hl.dsp.window.set_prop({ window = "address:" .. addr, prop = "inactive_border_color", value = inactive }))
end

--- @class Selection
local Selection = {}

--- Toggle select on the focused window, highlighting its border.
function Selection.toggle()
  local addr = get_active_address()
  if not addr then return end

  if SELECTED[addr] then
    local original = SELECTED[addr]
    SELECTED[addr] = nil
    set_border(addr, original.active, original.inactive)
  else
    SELECTED[addr] = get_theme_borders()
    set_border(addr, SELECTION_COLOR, SELECTION_COLOR)
  end
end

--- Deselect every window and restore its borders. Called when the Windows submap exits.
function Selection.clear()
  for addr, original in pairs(SELECTED) do
    set_border(addr, original.active, original.inactive)
    SELECTED[addr] = nil
  end
end

--- Swap the focused window with the one selected window, then clear the selection.
function Selection.swap()
  local active = get_active_address()
  local target, count = nil, 0
  for addr in pairs(SELECTED) do
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
    local any = next(SELECTED)
    if not any then
      fn()
      return
    end

    local original = get_active_address()
    for addr in pairs(SELECTED) do
      hl.dispatch(hl.dsp.focus({ window = "address:" .. addr }))
      fn()
    end
    if original then hl.dispatch(hl.dsp.focus({ window = "address:" .. original })) end
  end
end

return Selection
