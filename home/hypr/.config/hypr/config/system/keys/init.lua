-- home/hypr/.config/hypr/keys/init.lua
--
--    ██╗  ██╗███████╗██╗   ██╗██████╗ ██╗███╗   ██╗██████╗ ███████╗
--    ██║ ██╔╝██╔════╝╚██╗ ██╔╝██╔══██╗██║████╗  ██║██╔══██╗██╔════╝
--    █████╔╝ █████╗   ╚████╔╝ ██████╔╝██║██╔██╗ ██║██║  ██║███████╗
--    ██╔═██╗ ██╔══╝    ╚██╔╝  ██╔══██╗██║██║╚██╗██║██║  ██║╚════██║
--    ██║  ██╗███████╗   ██║   ██████╔╝██║██║ ╚████║██████╔╝███████║
--    ╚═╝  ╚═╝╚══════╝   ╚═╝   ╚═════╝ ╚═╝╚═╝  ╚═══╝╚═════╝ ╚══════╝
--

local Config = require("config")
local Utils = require("lib.utils")
local Workspaces = require("lib.workspaces")
local run_script = Utils.run_script

local LEADER = Config.leader .. " " -- Add space now
local TERM = Config.app.term
local FILES = Config.app.file_manager
local MENU = Config.app.menu

local DIR_INPUT = {
  { vim = "H", arrow = "Left", dir = "l", label = "Left" },
  { vim = "L", arrow = "Right", dir = "r", label = "Right" },
  { vim = "K", arrow = "Up", dir = "u", label = "Up" },
  { vim = "J", arrow = "Down", dir = "d", label = "Down" },
}

-- Bind a dispatcher for every direction. desc_prefix .. d.label fills the description.
-- vim_mode gates hjkl; arrow keys always register.
local function bind_dir_inputs(mods, make_dsp, desc_prefix, opts)
  for _, d in ipairs(DIR_INPUT) do
    local flags = {}
    for k, v in pairs(opts or {}) do
      flags[k] = v
    end
    flags.description = desc_prefix .. d.label
    if Config.vim_mode then hl.bind(mods .. " + " .. d.vim, make_dsp(d), flags) end
    hl.bind(mods .. " + " .. d.arrow, make_dsp(d), flags)
  end
end

-- ──────────────────────────────────────────────────────────────────────────── #
-- !-- Flag References
-- ──────────────────────────────────────────────────────────────────────────── #
-- Flag                 | Description
-- locked (l)           | Will also work when an input inhibitor (e.g. a lockscreen) is active.
-- release (r)          | Will trigger on release of a key.
-- click (c)            | Will trigger on release of a key or button as long as the mouse cursor stays inside binds:drag_threshold.
-- drag (g)             | Will trigger on release of a key or button as long as the mouse cursor moves outside binds:drag_threshold.
-- long_press (o)       | Will trigger on long press of a key.
-- repeating (e)        | Will repeat when held.
-- non_consuming (n)    | Key/mouse events will be passed to the active window in addition to triggering the dispatcher.
-- auto_consuming       | Key/mouse events will be passed to the active window if the dispatcher doesn’t succeed.
-- mouse (m)            | See the dedicated Mouse Binds section.
-- transparent (t)      | Cannot be shadowed by other binds.
-- ignore_mods (i)      | Will ignore modifiers.
-- separate (s)         | Will arbitrarily combine keys between each mod/key, see Keysym combos.
-- description (d)      | Will allow you to write a description for your bind.
-- bypass (p)           | Bypasses the app’s requests to inhibit keybinds.
-- submap_universal (u) | Will be active no matter the submap.
-- devices              | Allow binds to be set per device. See Per-Device Binds

-- ──────────────────────────────────────────────────────────────────────────── #
-- !-- Basic Navigation
-- ──────────────────────────────────────────────────────────────────────────── #

local set_basic_navigation = function()
  hl.bind(LEADER .. "+ ESCAPE", hl.dsp.submap("reset"), { desc = "Reset Submaps", submap_universal = true })
  hl.bind(LEADER .. "+ C", hl.dsp.window.close(), { desc = "Close Window" })
  hl.bind(LEADER .. "+ F", hl.dsp.window.fullscreen({ action = "toggle" }), { desc = "Toggle Fullscreen" })
  hl.bind(
    LEADER .. "+ T",
    hl.dsp.exec_cmd("hyprctl dispatch submap reset; $MENU -i -show hyprwindow"),
    { desc = "Find window by name" }
  )
  hl.bind(
    LEADER .. "+ SHIFT + T",
    hl.dsp.exec_cmd("hyprctl dispatch submap reset; ~/.config/hypr/scripts/rofi-hyprwindow.sh --move"),
    { desc = "Move window next to another window" }
  )
  hl.bind(
    LEADER .. "+ CTRL + SHIFT + T",
    hl.dsp.exec_cmd("hyprctl dispatch submap reset; ~/.config/hypr/scripts/rofi-hyprwindow.sh --move-silent"),
    { desc = "Move window silently next to another window" }
  )

  -- !--- Focus Movement
  bind_dir_inputs(
    LEADER,
    function(d) return hl.dsp.focus({ direction = d.dir }) end,
    "Focus ",
    { submap_universal = true }
  )
  hl.bind(LEADER .. "+ TAB", hl.dsp.focus({ workspace = "previous" }), { description = "Go to Last Active WS" })

  -- !--- Monitor Navigation
  local get_monitor_selector = Workspaces.get_monitor_selector
  for i, entry in ipairs(Config.monitors) do
    local sel = get_monitor_selector(entry)
    if sel then
      hl.bind(LEADER .. "+ CTRL + " .. i, hl.dsp.focus({ monitor = sel }), { description = "Focus Monitor " .. i })
      hl.bind(
        LEADER .. "+ CTRL + SHIFT + " .. i,
        hl.dsp.window.move({ monitor = sel, follow = true }),
        { description = "Move to Monitor " .. i }
      )
    end
  end

  -- !--- Move Windows to Monitor
  bind_dir_inputs(
    LEADER .. "+ SHIFT",
    function(d) return hl.dsp.window.move({ direction = d.dir }) end,
    "Move Window ",
    { submap_universal = true }
  )

  -- !--- Workspace Navigation
  local PERSISTENT_WS = Config.persistent_workspaces
  local get_ws_id = Workspaces.get_ws_id
  local cycle_local_ws = Workspaces.cycle_local_ws
  local move_window_local_ws = Workspaces.move_window_local_ws

  -- Focus/Move Windows
  for i = 1, PERSISTENT_WS do
    local key = i % 10

    hl.bind(
      LEADER .. "+ " .. key,
      function() hl.dispatch(hl.dsp.focus({ workspace = get_ws_id(i) })) end,
      { submap_universal = true, description = "Go to Workspace " .. i }
    )

    hl.bind(
      LEADER .. "+ SHIFT + " .. key,
      function() hl.dispatch(hl.dsp.window.move({ workspace = get_ws_id(i) })) end,
      { description = "Move to Workspace " .. i }
    )
  end

  -- Persistent workspace binds to move windows/workspaces relative to the active monitor
  if PERSISTENT_WS then
    hl.bind(
      LEADER .. "+ CTRL + L",
      function() cycle_local_ws("next") end,
      { repeating = true, description = "Next WS on Monitor" }
    )
    hl.bind(
      LEADER .. "+ CTRL + H",
      function() cycle_local_ws("prev") end,
      { repeating = true, description = "Prev WS on Monitor" }
    )
    hl.bind(
      LEADER .. "+ CTRL + K",
      function() move_window_local_ws("next") end,
      { description = "Move window to next WS" }
    )
    hl.bind(
      LEADER .. "+ CTRL + J",
      function() move_window_local_ws("prev") end,
      { description = "Move window to prev WS" }
    )
  end

  -- !--- Scratchpad
  hl.bind(
    LEADER .. "+ S",
    hl.dsp.workspace.toggle_special("scratchpad"),
    { description = "Toggle Scratchpad", submap_universal = true }
  )
  hl.bind(
    LEADER .. "+ SHIFT + S",
    hl.dsp.window.move({ workspace = "special:scratchpad" }),
    { description = "Move Window to Scratchpad", submap_universal = true }
  )
end

-- !--- Marks
-- TODO: Setup later when mark works
-- bindd = LEADER, M, +Mark, exec, $HYPRVIM_WHICH_KEY --delay=0; $HYPRVIM_MARKS after reset && hyprctl dispatch submap SET-MARK
-- bindd = LEADER+CTRL, M, +Delete Mark, exec, $HYPRVIM_WHICH_KEY --delay=0; $HYPRVIM_MARKS after reset && hyprctl dispatch submap DELETE-MARK
-- bindd = LEADER, APOSTROPHE, +Jump, exec, $HYPRVIM_WHICH_KEY --delay=0; $HYPRVIM_MARKS after reset && hyprctl dispatch submap JUMP-MARK
-- bindd = LEADER, GRAVE, +Jump Exit, exec, $HYPRVIM_WHICH_KEY --delay=0; $HYPRVIM_MARKS after reset && hyprctl dispatch submap JUMP-MARK
-- bindd = LEADER+SHIFT, M, List Marks, exec, $HYPRVIM_MARKS list

-- ──────────────────────────────────────────────────────────────────────────── #
-- !-- Mouse Controls
-- ──────────────────────────────────────────────────────────────────────────── #
local set_mouse_controls = function()
  -- !--- Scroll Through Workspaces
  hl.bind(LEADER .. "+ mouse_down", hl.dsp.focus({ workspace = "e+1" }))
  hl.bind(LEADER .. "+ mouse_up", hl.dsp.focus({ workspace = "e-1" }))

  -- !--- Move/Resize Windows with Mouse
  hl.bind(LEADER .. "+ mouse:272", hl.dsp.window.drag(), { mouse = true })
  hl.bind(LEADER .. "+ mouse:273", hl.dsp.window.resize(), { mouse = true })
end

-- ──────────────────────────────────────────────────────────────────────────── #
-- !-- Utility Shortcuts
-- ──────────────────────────────────────────────────────────────────────────── #

local set_shortcuts = function()
  -- hl.bind(
  --   LEADER .. "+ SHIFT + SEMICOLON",
  --   hl.dsp.exec_cmd("$HYPRVIM_COMMAND after reset && $HYPRVIM_COMMAND prompt"),
  --   { description = "+Command" }
  -- )
  -- bindd = LEADER, SLASH, Launch Application, exec, $MENU -i -show drun
  hl.bind(LEADER .. "+ RETURN", hl.dsp.exec_cmd(TERM), { description = "Terminal" })
  hl.bind(LEADER .. "+ SHIFT + RETURN", hl.dsp.exec_cmd(MENU .. " -i -show run"), { description = "Run Script" })
  hl.bind(LEADER .. "+ CTRL + RETURN", hl.dsp.exec_cmd(MENU .. " -i -show ssh"), { description = "SSH Select" })
  hl.bind(LEADER .. "+ E", hl.dsp.exec_cmd(FILES), { description = "File Manager" })
  hl.bind("CTRL + SHIFT + ESCAPE", hl.dsp.exec_cmd(TERM .. " -e btop"), { description = "Task Manager" })
  hl.bind(
    LEADER .. "+ N",
    function()
      local Editor = require("hyprvim.vim.commands.editor")
      Editor.open({ ext = "md", insert_mode = true })
    end,
    -- hl.dsp.exec_cmd("wtype -M ctrl -k c -m ctrl && sleep 0.05 && $HYPRVIM_OPEN_VIM --copy-selected"),
    { description = "Edit Selection in NeoVim" }
  )
  hl.bind(LEADER .. "+ Y", hl.dsp.exec_cmd(TERM .. " -e yazi"), { description = "Yazi" })
  hl.bind(
    LEADER .. "+ O",
    hl.dsp.exec_cmd("hyprctl dispatch submap reset; " .. MENU .. " -i -show drun"),
    { description = "Application Launcher" }
  )
  hl.bind(
    LEADER .. "+ SHIFT + O",
    hl.dsp.exec_cmd("~/.config/hypr/lua/auto-launch-apps.lua"),
    { description = "Open App Autolauncher" }
  )
end

-- ──────────────────────────────────────────────────────────────────────────── #
-- !-- Tools
-- ──────────────────────────────────────────────────────────────────────────── #

local set_tools = function()
  hl.bind("Print", hl.dsp.exec_cmd(run_script("screenshot.sh", "hypr")), { description = "Print Options" })
  hl.bind(
    LEADER .. "+ P",
    hl.dsp.exec_cmd(run_script("screenshot.sh --pixel", "hypr")),
    { description = "Color Picker" }
  )
  hl.bind(
    "CTRL + Period",
    hl.dsp.exec_cmd(run_script("voxtype-with-media-pause.sh", "hypr")),
    { description = "Speech to Text" }
  )
  hl.bind(
    "CTRL + ALT + A",
    hl.dsp.exec_cmd(run_script("voxtype-with-media-pause.sh", "hypr")),
    { description = "Speech to Text" }
  )
  hl.bind(
    LEADER .. "+ CTRL + V",
    hl.dsp.exec_cmd(
      "cliphist list | " .. MENU .. " -i -dmenu -p 'Search clipboard history...' | cliphist decode | wl-copy"
    ),
    { description = "Clipboard History" }
  )
end

-- ──────────────────────────────────────────────────────────────────────────── #
-- !-- Volume / Media / Brightness
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
  hl.bind(
    LEADER .. "+ ALT + H",
    hl.dsp.exec_cmd("playerctl previous"),
    { description = "Previous Track", submap_universal = true, locked = true }
  )
  hl.bind(
    LEADER .. "+ ALT + L",
    hl.dsp.exec_cmd("playerctl next"),
    { description = "Next Track", submap_universal = true, locked = true }
  )
  hl.bind(
    LEADER .. "+ ALT + J",
    hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%-"),
    { description = "Volume Down", repeating = true, submap_universal = true, locked = true }
  )
  hl.bind(
    LEADER .. "+ ALT + K",
    hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"),
    { description = "Volume Up", repeating = true, submap_universal = true, locked = true }
  )
  hl.bind(
    LEADER .. "+ ALT + SPACE",
    hl.dsp.exec_cmd("playerctl play-pause"),
    { description = "Play/Pause Media", submap_universal = true, locked = true }
  )
  hl.bind(
    LEADER .. "+ ALT + M",
    hl.dsp.exec_cmd(run_script("focus-media-player.sh", "hypr")),
    { description = "Focus Media Window", submap_universal = true, locked = true }
  )

  -- !--- Media Keys
  hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true, submap_universal = true })
  hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true, submap_universal = true })
  hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true, submap_universal = true })
  hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true, submap_universal = true })
end

local init = function()
  set_basic_navigation()
  set_mouse_controls()
  set_shortcuts()
  set_tools()
  set_media_controls()
  require("config.system.keys.submap").setup()
end

init()
