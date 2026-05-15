-- home/hypr/.config/hypr/config/system/keys/init.lua
--
--    ██╗  ██╗███████╗██╗   ██╗██████╗ ██╗███╗   ██╗██████╗ ███████╗
--    ██║ ██╔╝██╔════╝╚██╗ ██╔╝██╔══██╗██║████╗  ██║██╔══██╗██╔════╝
--    █████╔╝ █████╗   ╚████╔╝ ██████╔╝██║██╔██╗ ██║██║  ██║███████╗
--    ██╔═██╗ ██╔══╝    ╚██╔╝  ██╔══██╗██║██║╚██╗██║██║  ██║╚════██║
--    ██║  ██╗███████╗   ██║   ██████╔╝██║██║ ╚████║██████╔╝███████║
--    ╚═╝  ╚═╝╚══════╝   ╚═╝   ╚═════╝ ╚═╝╚═╝  ╚═══╝╚═════╝ ╚══════╝
--

local Config = require("config") --- @class Config
local Workspaces = require("lib.workspaces") --- @class Workspaces
local Bind = require("lib.bind") --- @class Bind
local Scripts = require("lib.scripts") --- @class Scripts

local TERM = Config.app.term
local FILES = Config.app.gui_file_manager
local TUI_FILES = Config.app.tui_file_manager
local MENU = Config.app.menu

-- ──────────────────────────────────────────────────────────────────────────── #
-- !-- General Keybinds
--     Registers core window/workspace/monitor focus and movement binds.
-- ──────────────────────────────────────────────────────────────────────────── #
local set_general_keys = function()
  -- stylua: ignore start

  -- !--- General actions
  Bind.leader("ESCAPE", hl.dsp.submap("reset"), { desc = "Reset Submaps", submap_universal = true })
  Bind.leader("C", hl.dsp.window.close(), { desc = "Close Window" })
  Bind.leader("F", hl.dsp.window.fullscreen({ action = "toggle" }), { desc = "Toggle Fullscreen" })

  -- !--- Workspace Navigation (Basic)
  Bind.leader_dir("", function(d) return hl.dsp.focus({ direction = d.dir }) end, "Focus ", { submap_universal = true })
  Bind.leader("TAB", hl.dsp.focus({ workspace = "previous" }), { desc = "Go to Last Active WS" })

  -- !--- Scratchpad
  Bind.leader("S", hl.dsp.workspace.toggle_special("scratchpad"), { desc = "Toggle Scratchpad", submap_universal = true })
  Bind.leader("SHIFT + S", hl.dsp.window.move({ workspace = "special:scratchpad" }), { desc = "Move Window to Scratchpad", submap_universal = true })

  -- !--- Monitor Navigation
  for i = 1, math.max(#Config.monitors, 10) do
    local slot, key = i, i % 10
    Bind.leader("CTRL + " .. key, function()
      local sel = Workspaces.get_monitor_for_slot(slot)
      if sel then hl.dispatch(hl.dsp.focus({ monitor = sel })) end
    end, { desc = "Focus Monitor " .. i })
    Bind.leader("CTRL + SHIFT + " .. key, function()
      local sel = Workspaces.get_monitor_for_slot(slot)
      if sel then hl.dispatch(hl.dsp.window.move({ monitor = sel, follow = true })) end
    end, { desc = "Move to Monitor " .. i })
  end
  Bind.leader_dir( "SHIFT", function(d) return hl.dsp.window.move({ direction = d.dir }) end, "Move Window ", { submap_universal = true })
end

-- ──────────────────────────────────────────────────────────────────────────── #
-- !-- Workspace Navigation (Advanced)
--     Digit/cycle binds; persistent (relative to monitor) or default navigation
-- ──────────────────────────────────────────────────────────────────────────── #

--- Registers workspace binds for simple global workspaces (1-9, cycle prev/next).
local set_default_ws_navigation = function()
  -- Bind workspaces 1-10 to LEADER + digits, move with LEADER + SHIFT
  for i = 1, 10 do
    local key = i % 10
    Bind.leader("" .. key, hl.dsp.focus({ workspace = i }), { submap_universal = true, desc = "Go to Workspace " .. i })
    Bind.leader("SHIFT + " .. key, hl.dsp.window.move({ workspace = i }), { desc = "Move to Workspace " .. i })
  end

  -- Cycle through workspaces globally via LEADER + CTRL Left/Right, use Up/Down to move them
  local ws = {
    l = { hl.dsp.focus({ workspace = "e-1" }), { repeating = true, desc = "Prev WS" } },
    r = { hl.dsp.focus({ workspace = "e+1" }), { repeating = true, desc = "Next WS" } },
    d = { hl.dsp.window.move({ workspace = "e-1" }), { desc = "Move window to prev WS" } },
    u = { hl.dsp.window.move({ workspace = "e+1" }), { desc = "Move window to next WS" } },
  }
  Bind.leader_dir("CTRL", function(d) return ws[d.dir][1] end, nil, function(d) return ws[d.dir][2] end)
end

--- Registers workspace binds for monitor-pinned persistent workspaces (via `Config.persistent_workspaces`).
local set_persistent_ws_navigation = function()
  local get_ws_id = Workspaces.get_ws_id
  local cycle_local_ws = Workspaces.cycle_local_ws
  local move_window_local_ws = Workspaces.move_window_local_ws

  -- Bind local monitor-pinned workspaces to LEADER + digits, move with LEADER + SHIFT
  for i = 1, Config.persistent_workspaces do
    local key = i % 10
    -- stylua: ignore start
    Bind.leader("" .. key,         function() hl.dispatch(hl.dsp.focus({ workspace = get_ws_id(i) })) end,       { submap_universal = true, desc = "Go to Workspace " .. i })
    Bind.leader("SHIFT + " .. key, function() hl.dispatch(hl.dsp.window.move({ workspace = get_ws_id(i) })) end, { desc = "Move to Workspace " .. i })
  end

  -- Cycle through workspaces locally via LEADER + CTRL Left/Right, Use Up/Down to move them
  local ws = {
    l = { function() cycle_local_ws("prev") end, { repeating = true, desc = "Prev WS on Monitor" } },
    r = { function() cycle_local_ws("next") end, { repeating = true, desc = "Next WS on Monitor" } },
    d = { function() move_window_local_ws("prev") end, { desc = "Move window to prev WS" } },
    u = { function() move_window_local_ws("next") end, { desc = "Move window to next WS" } },
  }
  Bind.leader_dir("CTRL", function(d) return ws[d.dir][1] end, nil, function(d) return ws[d.dir][2] end)
end

-- ──────────────────────────────────────────────────────────────────────────── #
-- !-- Mouse Controls
--     Registers mouse binds: scroll to cycle workspaces, drag/resize windows
-- ──────────────────────────────────────────────────────────────────────────── #
local set_mouse_controls = function()
  -- !--- Scroll Through Workspaces
  Bind.leader("mouse_down", hl.dsp.focus({ workspace = "e+1", repeating = true }))
  Bind.leader("mouse_up", hl.dsp.focus({ workspace = "e-1", repeating = true }))

  -- !--- Move/Resize Windows with Mouse
  Bind.leader("mouse:272", hl.dsp.window.drag(), { mouse = true })
  Bind.leader("mouse:273", hl.dsp.window.resize(), { mouse = true })
end

-- ──────────────────────────────────────────────────────────────────────────── #
-- !-- Utility Shortcuts
--     Registers quick-launch binds: terminal, file manager, menu, editor, etc
-- ──────────────────────────────────────────────────────────────────────────── #
local set_shortcuts = function()
  -- stylua: ignore start
  Bind.leader("RETURN", hl.dsp.exec_cmd(TERM), { desc = "Terminal" })
  Bind.leader("SHIFT + RETURN", hl.dsp.exec_cmd(MENU .. " -i -show run"), { desc = "Run Script" })
  Bind.leader("CTRL + RETURN", hl.dsp.exec_cmd(MENU .. " -i -show ssh"), { desc = "SSH Select" })
  Bind.leader("E", hl.dsp.exec_cmd(FILES), { desc = "File Manager" })
  Bind.leader("SHIFT + E", hl.dsp.exec_cmd(TERM .. " -e " .. TUI_FILES), { desc = "TUI File Manager" })
  Bind.leader("N", function() require("hyprvim.vim.commands.editor").open({ ext = "md", insert_mode = true }) end, { desc = "Edit Selection in Vim" })
  Bind.leader("Y", hl.dsp.exec_cmd(TERM .. " -e yazi"), { desc = "Yazi" })
  Bind.leader_cmd("O", MENU .. " -i -show drun", { desc = "Open Application" })
  hl.bind("CTRL + SHIFT + ESCAPE", hl.dsp.exec_cmd(TERM .. " -e btop"), { desc = "Task Manager" })
end

-- ──────────────────────────────────────────────────────────────────────────── #
-- !-- Tools
--     Registers tool binds: screenshot, color picker, speech-to-text, etc
-- ──────────────────────────────────────────────────────────────────────────── #
local set_tools = function()
  -- stylua: ignore start

  -- !--- Screenshot / Color Picker
  Bind.cmd("Print", Scripts.screenshot, { desc = "Print Options" })
  Bind.leader("P", hl.dsp.exec_cmd(Scripts.screenshot .. " --pixel"), { desc = "Color Picker" })

  -- !--- Speech to text
  Bind.cmd("CTRL + PERIOD", Scripts.voxtype, { desc = "Speech to Text" })
  Bind.cmd("CTRL + ALT + A", Scripts.voxtype, { desc = "Speech to Text" })

  -- !--- Clipboard search
  local cmd_search_clipboard = "cliphist list | " .. MENU .. " -i -dmenu -p 'Search clipboard history...' | cliphist decode | wl-copy"
  Bind.leader_cmd("CTRL + V", cmd_search_clipboard, { desc = "Clipboard History" })

  -- !--- Window Finder / Mover via Menu
  Bind.leader_cmd("T", Config.app.menu .. " -i -show hyprwindow", { desc = "Find window by name" })
  Bind.leader_cmd("SHIFT + T", Scripts.window_selector .. " --move", { desc = "Move window to another window" })
  Bind.leader_cmd( "CTRL + SHIFT + T", Scripts.window_selector .. " --move-silent", { desc = "Silently move window to another window" })
end

-- ──────────────────────────────────────────────────────────────────────────── #
-- !-- Volume / Media / Brightness
--     Registers volume, brightness, playerctl, and hardware media key binds.
-- ──────────────────────────────────────────────────────────────────────────── #
local set_media_controls = function()
  -- !--- Volume and Brightness
  local rlu = { repeating = true, locked = true, submap_universal = true }
  hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), rlu)
  hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), rlu)
  hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), rlu)
  hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), rlu)
  hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl s 10%+"), rlu)
  hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl s 10%-"), rlu)

  -- !--- Media Controls
  -- stylua: ignore start
  local function set_pctl_opt(description) return { desc = description, submap_universal = true, locked = true } end
  local function set_vol_opt(description) return { desc = description, repeating = true, submap_universal = true, locked = true } end
  Bind.leader("ALT + H", hl.dsp.exec_cmd("playerctl previous"), set_pctl_opt("Previous Track"))
  Bind.leader("ALT + L", hl.dsp.exec_cmd("playerctl next"), set_pctl_opt("Next Track"))
  Bind.leader("ALT + J", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%-"), set_vol_opt("Volume Down"))
  Bind.leader("ALT + K", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), set_vol_opt("Volume Up"))
  Bind.leader("ALT + SPACE", hl.dsp.exec_cmd("playerctl play-pause"), set_pctl_opt("Play/Pause Media"))

  -- !--- Media Keys
  hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true, submap_universal = true })
  hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true, submap_universal = true })
  hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true, submap_universal = true })
  hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true, submap_universal = true })
end

-- ──────────────────────────────────────────────────────────────────────────── #
-- !-- HyprVim Shortcuts
--     Placeholder for HyprVim command/mark binds (pending HyprVim completion).
-- ──────────────────────────────────────────────────────────────────────────── #
local set_hyprvim_shortcuts = function()
  --TODO: Resolve once HyprVim is done
  -- Bind.leader_cmd("SHIFT + SEMICOLON", "$HYPRVIM_COMMAND after reset && $HYPRVIM_COMMAND prompt", { desc = "+Command" })
  -- !--- Marks
  -- bindd = LEADER, M, +Mark, exec, $HYPRVIM_WHICH_KEY --delay=0; $HYPRVIM_MARKS after reset && hyprctl dispatch submap SET-MARK
  -- bindd = LEADER+CTRL, M, +Delete Mark, exec, $HYPRVIM_WHICH_KEY --delay=0; $HYPRVIM_MARKS after reset && hyprctl dispatch submap DELETE-MARK
  -- bindd = LEADER, APOSTROPHE, +Jump, exec, $HYPRVIM_WHICH_KEY --delay=0; $HYPRVIM_MARKS after reset && hyprctl dispatch submap JUMP-MARK
  -- bindd = LEADER, GRAVE, +Jump Exit, exec, $HYPRVIM_WHICH_KEY --delay=0; $HYPRVIM_MARKS after reset && hyprctl dispatch submap JUMP-MARK
  -- bindd = LEADER+SHIFT, M, List Marks, exec, $HYPRVIM_MARKS list
end

-- ──────────────────────────────────────────────────────────────────────────── #
-- !-- Init
--     Registers all binds
-- ──────────────────────────────────────────────────────────────────────────── #
local init = function()
  local set_ws_navigation = Config.persistent_workspaces and set_persistent_ws_navigation or set_default_ws_navigation
  set_general_keys()
  set_ws_navigation()
  set_shortcuts()
  set_tools()
  set_media_controls()
  set_mouse_controls()
  set_hyprvim_shortcuts()
  require("config.system.keys.submap").setup()
end

init()
