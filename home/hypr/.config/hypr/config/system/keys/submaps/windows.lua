-- home/hypr/.config/hypr/config/system/keys/submaps/windows.lua

local Config = require("config")
local SubBind = require("lib.submap_bind")
local SUBMAP = require("config.system.keys.submap").map

local MENU = Config.app.menu

hl.define_submap(SUBMAP.windows.name, function()
  -- !--- Switch to other submaps ---
  SubBind.swap_to(SUBMAP.cursor, SUBMAP.cursor.fn)
  SubBind.swap_to(SUBMAP.resize)
  SubBind.swap_to(SUBMAP.screenshot)
  SubBind.swap_to(SUBMAP.system)
  SubBind.swap_to(SUBMAP.move)

  -- !--- Shortcuts ---
  SubBind.run("O", MENU .. " -i -show window", "Search windows")

    -- !--- Focus movement ---
    -- stylua: ignore start
    -- TODO: Use focus from ../init.lua
    hl.bind("H",     hl.dsp.exec_cmd("hyprctl dispatch movefocus l"), { description = "Focus Left" })
    hl.bind("L",     hl.dsp.exec_cmd("hyprctl dispatch movefocus r"), { description = "Focus Right" })
    hl.bind("K",     hl.dsp.exec_cmd("hyprctl dispatch movefocus u"), { description = "Focus Up" })
    hl.bind("J",     hl.dsp.exec_cmd("hyprctl dispatch movefocus d"), { description = "Focus Down" })
    hl.bind("Left",  hl.dsp.exec_cmd("hyprctl dispatch movefocus l"), { description = "Focus Left" })
    hl.bind("Right", hl.dsp.exec_cmd("hyprctl dispatch movefocus r"), { description = "Focus Right" })
    hl.bind("Up",    hl.dsp.exec_cmd("hyprctl dispatch movefocus u"), { description = "Focus Up" })
    hl.bind("Down",  hl.dsp.exec_cmd("hyprctl dispatch movefocus d"), { description = "Focus Down" })
    SubBind.exec("TAB", function() hl.dispatch(hl.dsp.focus({ workspace = "previous" })) end, "Last workspace")

    -- !--- Monitor navigation ---
    -- TODO: Use monitor count and focus script ../init.lua
    for i = 1, 4 do
      hl.bind(tostring(i), hl.dsp.exec_cmd("hyprctl dispatch focusmonitor " .. (i - 1)), { description = "Monitor " .. i })
    end

    -- !--- Move windows ---
    -- TODO: Use movewindow from ../init.lua
    hl.bind("SHIFT + H",     hl.dsp.exec_cmd("hyprctl dispatch movewindow l"), { description = "Move Left" })
    hl.bind("SHIFT + L",     hl.dsp.exec_cmd("hyprctl dispatch movewindow r"), { description = "Move Right" })
    hl.bind("SHIFT + K",     hl.dsp.exec_cmd("hyprctl dispatch movewindow u"), { description = "Move Up" })
    hl.bind("SHIFT + J",     hl.dsp.exec_cmd("hyprctl dispatch movewindow d"), { description = "Move Down" })
    hl.bind("SHIFT + Left",  hl.dsp.exec_cmd("hyprctl dispatch movewindow l"), { description = "Move Left" })
    hl.bind("SHIFT + Right", hl.dsp.exec_cmd("hyprctl dispatch movewindow r"), { description = "Move Right" })
    hl.bind("SHIFT + Up",    hl.dsp.exec_cmd("hyprctl dispatch movewindow u"), { description = "Move Up" })
    hl.bind("SHIFT + Down",  hl.dsp.exec_cmd("hyprctl dispatch movewindow d"), { description = "Move Down" })

    -- !--- Workspace navigation (split-monitor plugin) ---
    -- TODO: Use local function here from ../init.lua
    hl.bind("CTRL + H",     hl.dsp.exec_cmd("hyprctl dispatch split-cycleworkspaces prev"), { description = "Prev Workspace" })
    hl.bind("CTRL + L",     hl.dsp.exec_cmd("hyprctl dispatch split-cycleworkspaces next"), { description = "Next Workspace" })
    hl.bind("CTRL + K",     hl.dsp.exec_cmd("hyprctl dispatch split-movetoworkspace 1"),    { description = "WS Up" })
    hl.bind("CTRL + J",     hl.dsp.exec_cmd("hyprctl dispatch split-movetoworkspace -1"),   { description = "WS Down" })
    hl.bind("CTRL + Left",  hl.dsp.exec_cmd("hyprctl dispatch split-cycleworkspaces prev"), { description = "Prev Workspace" })
    hl.bind("CTRL + Right", hl.dsp.exec_cmd("hyprctl dispatch split-cycleworkspaces next"), { description = "Next Workspace" })
    hl.bind("CTRL + Up",    hl.dsp.exec_cmd("hyprctl dispatch split-movetoworkspace 1"),    { description = "WS Up" })
    hl.bind("CTRL + Down",  hl.dsp.exec_cmd("hyprctl dispatch split-movetoworkspace -1"),   { description = "WS Down" })

    -- !--- Move window to workspace ---
    for i = 1, 4 do
      hl.bind("SHIFT + " .. i, hl.dsp.exec_cmd("hyprctl dispatch split-movetoworkspace " .. i), { description = "Move to WS " .. i })
    end

  -- !--- Modes ---
  hl.bind("F",      hl.dsp.exec_cmd("hyprctl dispatch togglefloating"), { description = "Toggle Floating" })
  hl.bind("P",      hl.dsp.exec_cmd("hyprctl dispatch pseudo"), { description = "Toggle Pseudo (dwindle)" })
  hl.bind("S",      hl.dsp.exec_cmd("hyprctl dispatch togglesplit"), { description = "Toggle Split (dwindle)" })
  hl.bind("MINUS",  hl.dsp.exec_cmd("hyprctl dispatch togglesplit"), { description = "Toggle Split (dwindle)" })

  -- !--- Actions ---
  SubBind.exec("C", function() hl.dispatch(hl.dsp.window.kill()) end, "Close window")
  hl.bind("RETURN", hl.dsp.exec_cmd("hyprctl dispatch pass activewindow"), { description = "Confirm selection" })
  -- stylua: ignore end

  SubBind.bind_exits({ swallow_mispress = true })
end)
