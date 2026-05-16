--- Global keybinds — workspace navigation, shortcuts, tools, media, mouse.
--
--    ██╗  ██╗███████╗██╗   ██╗██████╗ ██╗███╗   ██╗██████╗ ███████╗
--    ██║ ██╔╝██╔════╝╚██╗ ██╔╝██╔══██╗██║████╗  ██║██╔══██╗██╔════╝
--    █████╔╝ █████╗   ╚████╔╝ ██████╔╝██║██╔██╗ ██║██║  ██║███████╗
--    ██╔═██╗ ██╔══╝    ╚██╔╝  ██╔══██╗██║██║╚██╗██║██║  ██║╚════██║
--    ██║  ██╗███████╗   ██║   ██████╔╝██║██║ ╚████║██████╔╝███████║
--    ╚═╝  ╚═╝╚══════╝   ╚═╝   ╚═════╝ ╚═╝╚═╝  ╚═══╝╚═════╝ ╚══════╝
--

local Config = require("config")
local Bind = require("lib.key.bind")
local Scripts = require("lib.scripts")
local Window = require("lib.actions.window")
local Workspace = require("lib.actions.workspace")
local Media = require("lib.actions.media")

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
  local function universal(description) return { submap_universal = true, desc = description } end

  -- !--- Global Helpers
  Bind.leader_key("ESCAPE",    function() hl.dispatch(hl.dsp.submap("reset")) end, universal("Reset Submaps"))
  Bind.leader_cmd("SLASH",     Scripts.keybind_help,                               universal("Keybind Help"))

  -- !--- Window
  Bind.leader_key("C",         Window.close(),             { desc = "Close Window" })
  Bind.leader_key("F",         Window.fullscreen_toggle(), { desc = "Toggle Fullscreen" })
  Bind.leader_key("TAB",       Workspace.focus_last(),            { desc = "Go to Last Active WS" })

  -- !--- Focus Direction
  Bind.leader_key({ "H", "LEFT" },  Window.focus_dir("l"), "Focus Left",  { submap_universal = true })
  Bind.leader_key({ "L", "RIGHT" }, Window.focus_dir("r"), "Focus Right", { submap_universal = true })
  Bind.leader_key({ "K", "UP" },    Window.focus_dir("u"), "Focus Up",    { submap_universal = true })
  Bind.leader_key({ "J", "DOWN" },  Window.focus_dir("d"), "Focus Down",  { submap_universal = true })

  -- !--- Scratchpad
  Bind.leader_key("S",         Window.toggle_scratchpad(), universal("Toggle Scratchpad"))
  Bind.leader_key("SHIFT + S", Window.move_to_scratchpad(), universal("Move to Scratchpad"))

  -- !--- Monitor Navigation
  for i = 1, math.max(#Config.monitors, 10) do
    local key = i % 10
    Bind.leader_key("CTRL + " .. key,         Window.focus_monitor(i), { desc = "Focus Monitor " .. i })
    Bind.leader_key("CTRL + SHIFT + " .. key, Window.move_to_monitor(i), { desc = "Move to Monitor " .. i })
  end

  -- !--- Move Window Direction
  Bind.leader_key({ "SHIFT + H", "SHIFT + LEFT" },  Window.move_dir("l"), "Move Window Left",  { submap_universal = true })
  Bind.leader_key({ "SHIFT + L", "SHIFT + RIGHT" }, Window.move_dir("r"), "Move Window Right", { submap_universal = true })
  Bind.leader_key({ "SHIFT + K", "SHIFT + UP" },    Window.move_dir("u"), "Move Window Up",    { submap_universal = true })
  Bind.leader_key({ "SHIFT + J", "SHIFT + DOWN" },  Window.move_dir("d"), "Move Window Down",  { submap_universal = true })
end

-- ──────────────────────────────────────────────────────────────────────────── #
-- !-- Workspace Navigation (Advanced)
--     Digit/cycle binds; persistent (relative to monitor) or default navigation
-- ──────────────────────────────────────────────────────────────────────────── #

--- Registers workspace binds for simple global workspaces (1-9, cycle prev/next).
local set_default_ws_navigation = function()
  -- stylua: ignore start
  for i = 1, 10 do
    local key = i % 10
    Bind.leader_key("" .. key,         Workspace.focus(i), { submap_universal = true, desc = "Go to Workspace " .. i })
    Bind.leader_key("SHIFT + " .. key, Workspace.move(i),  { desc = "Move to Workspace " .. i })
  end

  -- CTRL + Left/Right to cycle prev/next workspace, Up/Down to move window
  Bind.leader_key({ "CTRL + H", "CTRL + LEFT" },  Workspace.cycle_prev(), "Prev WS",                { repeating = true })
  Bind.leader_key({ "CTRL + L", "CTRL + RIGHT" }, Workspace.cycle_next(), "Next WS",                { repeating = true })
  Bind.leader_key({ "CTRL + J", "CTRL + DOWN" },  Workspace.move_prev(),  "Move window to prev WS")
  Bind.leader_key({ "CTRL + K", "CTRL + UP" },    Workspace.move_next(),  "Move window to next WS")
end

--- Registers workspace binds for monitor-pinned persistent workspaces.
local set_persistent_ws_navigation = function()
  -- stylua: ignore start
  for i = 1, Config.persistent_workspaces do
    local key = i % 10
    Bind.leader_key("" .. key,         Workspace.focus_local(i), { submap_universal = true, desc = "Go to Workspace " .. i })
    Bind.leader_key("SHIFT + " .. key, Workspace.move_local(i),  { desc = "Move to Workspace " .. i })
  end

  Bind.leader_key({ "CTRL + H", "CTRL + LEFT" },  Workspace.cycle_local("prev"),        "Prev WS on Monitor",      { repeating = true })
  Bind.leader_key({ "CTRL + L", "CTRL + RIGHT" }, Workspace.cycle_local("next"),        "Next WS on Monitor",      { repeating = true })
  Bind.leader_key({ "CTRL + J", "CTRL + DOWN" },  Workspace.move_window_local("prev"),  "Move window to prev WS")
  Bind.leader_key({ "CTRL + K", "CTRL + UP" },    Workspace.move_window_local("next"),  "Move window to next WS")
end

-- ──────────────────────────────────────────────────────────────────────────── #
-- !-- Mouse Controls
--     Registers mouse binds: scroll to cycle workspaces, drag/resize windows
-- ──────────────────────────────────────────────────────────────────────────── #
local set_mouse_controls = function()
  -- stylua: ignore start
  Bind.leader_key("mouse_down", Workspace.scroll_next(), { hidden = true })
  Bind.leader_key("mouse_up",   Workspace.scroll_prev(), { hidden = true })
  Bind.leader_key("mouse:272",  Window.drag(),        { mouse = true })
  Bind.leader_key("mouse:273",  Window.resize_mouse(), { mouse = true })
end

-- ──────────────────────────────────────────────────────────────────────────── #
-- !-- Utility Shortcuts
--     Registers quick-launch binds: terminal, file manager, menu, editor, etc
-- ──────────────────────────────────────────────────────────────────────────── #
local set_shortcuts = function()
  -- stylua: ignore start
  Bind.leader_cmd("RETURN",           TERM,                                    { desc = "Terminal" })
  Bind.leader_cmd("SHIFT + RETURN",   MENU .. " -i -show run",                 { desc = "Run Script" })
  Bind.leader_cmd("CTRL + RETURN",    MENU .. " -i -show ssh",                 { desc = "SSH Select" })
  Bind.leader_cmd("E",                FILES,                                   { desc = "File Manager" })
  Bind.leader_cmd("SHIFT + E",        TERM .. " -e " .. TUI_FILES,             { desc = "TUI File Manager" })
  Bind.leader_key("N",                function() require("hyprvim.vim.commands.editor").open({ insert_mode = false }) end, { desc = "Edit Selection in Vim" })
  Bind.leader_cmd("Y",                TERM .. " -e yazi",                      { desc = "Yazi" })
  Bind.leader_cmd("O",                MENU .. " -i -show drun",                { desc = "Open Application" })
  Bind.cmd("CTRL + SHIFT + ESCAPE",   TERM .. " -e btop",                      { desc = "Task Manager" })
  -- stylua: ignore end
end

-- ──────────────────────────────────────────────────────────────────────────── #
-- !-- Tools
--     Registers tool binds: screenshot, color picker, speech-to-text, etc
-- ──────────────────────────────────────────────────────────────────────────── #
local set_tools = function()
  -- stylua: ignore start
  -- !--- Screenshot / Color Picker
  Bind.cmd("Print",          Scripts.screenshot,                { desc = "Print Options" })
  Bind.leader_cmd("P",       Scripts.screenshot .. " --pixel",  { desc = "Color Picker" })

  -- !--- Speech to text
  Bind.cmd("CTRL + PERIOD",  Scripts.voxtype, { desc = "Speech to Text" })
  Bind.cmd("CTRL + ALT + A", Scripts.voxtype, { desc = "Speech to Text" })

  -- !--- Clipboard search
  local cmd_search_clipboard = "cliphist list | "
    .. MENU
    .. " -i -dmenu -p 'Search clipboard history...' | cliphist decode | wl-copy"
  Bind.leader_cmd("CTRL + V", cmd_search_clipboard, { desc = "Clipboard History" })

  -- !--- Window Finder / Mover via Menu
  Bind.leader_cmd("T",             MENU .. " -i -show hyprwindow",              { desc = "Find window" })
  Bind.leader_cmd("SHIFT + T",     Scripts.window_selector .. " --move",        { desc = "Move to window" })
  Bind.leader_cmd("CTRL + SHIFT + T", Scripts.window_selector .. " --move-silent", { desc = "Silent move to window" })
end

-- ──────────────────────────────────────────────────────────────────────────── #
-- !-- Volume / Media / Brightness
--     Registers volume, brightness, playerctl, and hardware media key binds.
-- ──────────────────────────────────────────────────────────────────────────── #
local set_media_controls = function()
  -- stylua: ignore start
  -- !--- Volume and Brightness (hardware keys)
  Bind.key("XF86AudioRaiseVolume",  Media.volume_up(),     "Volume Up",       { repeating = true, locked = true, submap_universal = true })
  Bind.key("XF86AudioLowerVolume",  Media.volume_down(),   "Volume Down",     { repeating = true, locked = true, submap_universal = true })
  Bind.key("XF86AudioMute",         Media.mute(),          "Mute",            { locked = true, submap_universal = true })
  Bind.key("XF86AudioMicMute",      Media.mute_mic(),      "Mute Mic",        { locked = true, submap_universal = true })
  Bind.key("XF86MonBrightnessUp",   Media.brightness_up(), "Brightness Up",   { repeating = true, locked = true, submap_universal = true })
  Bind.key("XF86MonBrightnessDown", Media.brightness_down(), "Brightness Down", { repeating = true, locked = true, submap_universal = true })

  -- !--- Media Controls (leader binds)
  local pctl = { submap_universal = true, locked = true }
  local vol  = { repeating = true, submap_universal = true, locked = true }
  Bind.leader_key("ALT + H",     Media.prev(),        "Previous Track",   pctl)
  Bind.leader_key("ALT + L",     Media.next(),        "Next Track",       pctl)
  Bind.leader_key("ALT + J",     Media.volume_down(), "Volume Down",      vol)
  Bind.leader_key("ALT + K",     Media.volume_up(),   "Volume Up",        vol)
  Bind.leader_key("ALT + SPACE", Media.play_pause(),  "Play/Pause Media", pctl)

  -- !--- Media Keys (hardware)
  Bind.key("XF86AudioNext",  Media.next(),       "Next Track",   { locked = true, submap_universal = true })
  Bind.key("XF86AudioPause", Media.play_pause(), "Pause Media",  { locked = true, submap_universal = true })
  Bind.key("XF86AudioPlay",  Media.play_pause(), "Play Media",   { locked = true, submap_universal = true })
  Bind.key("XF86AudioPrev",  Media.prev(),       "Prev Track",   { locked = true, submap_universal = true })
  -- stylua: ignore end
end

-- ──────────────────────────────────────────────────────────────────────────── #
-- !-- HyprVim Shortcuts
--     Placeholder for HyprVim command/mark binds (pending HyprVim completion).
-- ──────────────────────────────────────────────────────────────────────────── #
local set_hyprvim_shortcuts = function()
  --TODO: Resolve once HyprVim is done
end

--- @class Global
local Global = {}

function Global.setup()
  local set_ws_navigation = Config.persistent_workspaces and set_persistent_ws_navigation or set_default_ws_navigation
  set_general_keys()
  set_shortcuts()
  set_ws_navigation()
  set_tools()
  set_media_controls()
  set_mouse_controls()
  set_hyprvim_shortcuts()
end

return Global
