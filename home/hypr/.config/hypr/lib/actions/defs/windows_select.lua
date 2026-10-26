-- Actions for the Windows submap's selection: select a window, then act on every selected window at once (or on the
-- focused one when none is selected). Keyless; the Windows rows bind them. The selection itself is in
-- lib/actions/selection.lua so it persists between presses, and is required on use so a headless load needs no session.
local Act = require("lib.act") ---@class ActionLib

local DIRECTION_CODE = { left = "l", down = "d", up = "u", right = "r" }
local DIRECTIONS = { "left", "down", "up", "right" }

--- @return SelectionActions
local function selection() return require("lib.actions.selection") end

--- A `run` that applies `Window[name](...)` to each selected window.
--- @param name string
--- @param ...  any
--- @return fun()
local function on_selected(name, ...)
  local fixed = { ... }
  return function() selection().for_selected(require("lib.actions.window")[name](table.unpack(fixed)))() end
end

--- @return boolean
local function per_monitor() return require("config").persistent_workspaces and true or false end

Act.define("windows.select_toggle", {
  label = "Select Window",
  intent = "Add the focused window to the Windows selection, or take it out.",
  run = function() selection().toggle() end,
})

Act.define("windows.swap_selected", {
  label = "Swap with Selected",
  intent = "Swap the focused window with the one selected window, then clear the selection.",
  run = function() selection().swap() end,
})

Act.define("windows.clear_selection", {
  label = "Clear Selection",
  intent = "Deselect every window and restore its borders.",
  run = function() selection().clear() end,
})

Act.define("windows.confirm", {
  label = "Confirm Selection",
  intent = "Pass the Return key through to the focused window.",
  run = function() require("lib.actions.window").pass_to_active()() end,
})

Act.define("windows.step_float", {
  label = "Step Floating Window",
  intent = "Focus the previous or next floating window on this workspace.",
  params = { { name = "dir", type = "enum", values = { "prev", "next" } } },
  run = function(dir) require("lib.actions.window").cycle_float(dir)() end,
})

Act.define("windows.close_selected", {
  label = "Close Selected",
  intent = "Kill every selected window, or the focused one when none is selected.",
  run = on_selected("kill"),
})

Act.define("windows.float_selected", {
  label = "Toggle Floating (Selected)",
  intent = "Float or tile every selected window, or the focused one when none is selected.",
  run = on_selected("float_toggle"),
})

Act.define("windows.pseudo_selected", {
  label = "Toggle Pseudo (Selected)",
  intent = "Toggle pseudo-tiling on every selected window, or the focused one when none is selected.",
  run = on_selected("pseudo_toggle"),
})

Act.define("windows.split_selected", {
  label = "Toggle Split (Selected)",
  intent = "Toggle the split direction of every selected window, or the focused one when none is selected.",
  run = on_selected("layout_toggle"),
})

Act.define("windows.move_selected", {
  label = "Move Selected",
  intent = "Move every selected window one place in a direction, or the focused one when none is selected.",
  params = { { name = "dir", type = "enum", values = DIRECTIONS } },
  run = function(dir) on_selected("move_dir", DIRECTION_CODE[dir])() end,
})

Act.define("windows.workspace_selected", {
  label = "Send Selected to Adjacent Workspace",
  intent = "Move every selected window (or the focused one) to the previous or next workspace, on this monitor with persistent workspaces.",
  params = { { name = "dir", type = "enum", values = { "prev", "next" } } },
  run = function(dir)
    local Workspace = require("lib.actions.workspace")
    local move
    if per_monitor() then
      move = Workspace.move_window_local(dir)
    elseif dir == "next" then
      move = Workspace.move_next()
    else
      move = Workspace.move_prev()
    end
    selection().for_selected(move)()
  end,
})

Act.define("windows.workspace_move_selected", {
  label = "Send Selected to Workspace",
  intent = "Move every selected window (or the focused one) to workspace n, or to slot n of this monitor with persistent workspaces.",
  params = { { name = "n", type = "int" } },
  run = function(n)
    local Workspace = require("lib.actions.workspace")
    selection().for_selected(per_monitor() and Workspace.move_local(n) or Workspace.move(n))()
  end,
})
