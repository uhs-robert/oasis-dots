-- home/hypr/.config/hypr/config/system/keys/submaps/windows.lua

local Config = require("config") ---@class Config
local SubBind = require("lib.submap_bind") ---@class SubBind
local Workspaces = require("lib.workspaces") ---@class Workspaces
local SUBMAP = require("config.system.keys.submap").map

local MENU = Config.app.menu

local DIR_INPUTS = {
  { key = "H", arrow = "Left", dir = "l", label = "Left" },
  { key = "J", arrow = "Down", dir = "d", label = "Down" },
  { key = "K", arrow = "Up", dir = "u", label = "Up" },
  { key = "L", arrow = "Right", dir = "r", label = "Right" },
}

hl.define_submap(SUBMAP.windows.name, function()
  -- !--- Switch to other submaps ---
  SubBind.swap_to(SUBMAP.cursor, { key = "X", fn = SUBMAP.cursor.fn })
  SubBind.swap_to(SUBMAP.resize, { key = "R" })
  SubBind.swap_to(SUBMAP.screenshot, { key = "I" })
  SubBind.swap_to(SUBMAP.system, { key = "Q" })
  SubBind.swap_to(SUBMAP.move, { key = "M" })

  -- !--- Shortcuts ---
  SubBind.run("O", MENU .. " -i -show window", "Search windows")

  -- !--- Focus movement ---
  for _, d in ipairs(DIR_INPUTS) do
    hl.bind(d.key, hl.dsp.focus({ direction = d.dir }), { description = "Focus " .. d.label })
    hl.bind(d.arrow, hl.dsp.focus({ direction = d.dir }), { description = "Focus " .. d.label })
  end
  SubBind.exec("TAB", function() hl.dispatch(hl.dsp.focus({ workspace = "previous" })) end, "Last workspace")

  -- !--- Monitor navigation ---
  for i = 1, math.max(#Config.monitors, 10) do
    local slot, key = i, i % 10
    hl.bind(tostring(key), function()
      local sel = Workspaces.get_monitor_for_slot(slot)
      if sel then hl.dispatch(hl.dsp.focus({ monitor = sel })) end
    end, { description = "Monitor " .. i })
  end

  -- !--- Move windows ---
  for _, d in ipairs(DIR_INPUTS) do
    hl.bind("SHIFT + " .. d.key, hl.dsp.window.move({ direction = d.dir }), { description = "Move " .. d.label })
    hl.bind("SHIFT + " .. d.arrow, hl.dsp.window.move({ direction = d.dir }), { description = "Move " .. d.label })
  end

  -- !--- Workspace navigation ---
  local ws_dsp
  if Config.persistent_workspaces then
    ws_dsp = {
      l = { function() Workspaces.cycle_local_ws("prev") end, "Prev Workspace" },
      d = { function() Workspaces.move_window_local_ws("prev") end, "Move to Prev WS" },
      u = { function() Workspaces.move_window_local_ws("next") end, "Move to Next WS" },
      r = { function() Workspaces.cycle_local_ws("next") end, "Next Workspace" },
    }
  else
    ws_dsp = {
      l = { hl.dsp.focus({ workspace = "e-1" }), "Prev Workspace" },
      d = { hl.dsp.window.move({ workspace = "e-1" }), "Move to Prev WS" },
      u = { hl.dsp.window.move({ workspace = "e+1" }), "Move to Next WS" },
      r = { hl.dsp.focus({ workspace = "e+1" }), "Next Workspace" },
    }
  end
  for _, d in ipairs(DIR_INPUTS) do
    hl.bind("CTRL + " .. d.key, ws_dsp[d.dir][1], { description = ws_dsp[d.dir][2] })
    hl.bind("CTRL + " .. d.arrow, ws_dsp[d.dir][1], { description = ws_dsp[d.dir][2] })
  end

  -- !--- Move window to workspace ---
  for i = 1, Config.persistent_workspaces or 10 do
    local key = i % 10
    local dsp = Config.persistent_workspaces
        and function() hl.dispatch(hl.dsp.window.move({ workspace = Workspaces.get_ws_id(i) })) end
      or hl.dsp.window.move({ workspace = i })
    hl.bind("SHIFT + " .. key, dsp, { description = "Move to WS " .. i })
  end

  -- !--- Modes ---
  -- stylua: ignore start
  hl.bind("F",     hl.dsp.exec_cmd("hyprctl dispatch togglefloating"), { description = "Toggle Floating" })
  hl.bind("P",     hl.dsp.exec_cmd("hyprctl dispatch pseudo"),         { description = "Toggle Pseudo (dwindle)" })
  hl.bind("S",     hl.dsp.exec_cmd("hyprctl dispatch togglesplit"),    { description = "Toggle Split (dwindle)" })
  hl.bind("MINUS", hl.dsp.exec_cmd("hyprctl dispatch togglesplit"),    { description = "Toggle Split (dwindle)" })
  -- stylua: ignore end

  -- !--- Actions ---
  SubBind.exec("C", hl.dsp.window.kill(), "Close window")
  hl.bind("RETURN", hl.dsp.exec_cmd("hyprctl dispatch pass activewindow"), { description = "Confirm selection" })

  -- !--- WhichKey ---
  hl.bind("SHIFT + SLASH", function() require("hyprvim.whichkey").toggle() end)

  -- !--- Exit ---
  SubBind.bind_exits({ swallow_mispress = true })
end)
