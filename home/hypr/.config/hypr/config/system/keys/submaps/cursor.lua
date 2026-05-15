-- home/hypr/.config/hypr/config/system/keys/submaps/cursor.lua

local SubBind = require("lib.submap_bind") ---@class SubBind
local SUBMAP = require("config.system.keys.submap").map
local CURSOR = SUBMAP.cursor

local restore_cursor_config = function(defaults)
  hl.config({ cursor = { inactive_timeout = defaults.timeout, hide_on_key_press = defaults.hide } })
end

local function swap_submap(name)
  restore_cursor_config(CURSOR.defaults)
  hl.dispatch(hl.dsp.submap(name))
end

--- Cursor
hl.define_submap(CURSOR.name, function()
  -- !--- Switch to other submaps ---
  -- stylua: ignore start
  SubBind.swap_to(SUBMAP.windows,    function() swap_submap(SUBMAP.windows.name) end)
  SubBind.swap_to(SUBMAP.resize,     function() swap_submap(SUBMAP.resize.name) end)
  SubBind.swap_to(SUBMAP.screenshot, function() swap_submap(SUBMAP.screenshot.name) end)
  SubBind.swap_to(SUBMAP.system,     function() swap_submap(SUBMAP.system.name) end)
  -- stylua: ignore end

  -- !--- Floating Mode: Cursor click/move (vimium style) ---
  -- stylua: ignore start
  SubBind.run_then_swap_to("F",         "wl-kbptr -o modes=floating,click -o mode_floating.source=detect", CURSOR.name, "Floating (Click)")
  SubBind.run_then_swap_to("SHIFT + F", "wl-kbptr -o modes=floating -o mode_floating.source=detect",       CURSOR.name, "Floating Cursor Move")
  SubBind.run_then_fn( "CTRL + F",  "wl-kbptr -o modes=floating,click -o mode_floating.source=detect", function() restore_cursor_config(CURSOR.defaults) end, "Floating (Click/Exit)")

  -- !--- Tiling Mode: Cursor click/move ---
  SubBind.run_then_swap_to("T",         "wl-kbptr -o modes=tile,click", CURSOR.name, "Tiling (Click)")
  SubBind.run_then_swap_to("SHIFT + T", "wl-kbptr -o modes=tile",       CURSOR.name, "Tiling Cursor Move")
  SubBind.run_then_fn( "CTRL + T",  "wl-kbptr -o modes=tile,click", function() restore_cursor_config(CURSOR.defaults) end, "Tiling (Click/Exit)")
  -- stylua: ignore end

  -- !--- Cursor movement ---
  local DIRS = {
    { key = "H", x = -1, y = 0, label = "Left" },
    { key = "J", x = 0, y = 1, label = "Down" },
    { key = "K", x = 0, y = -1, label = "Up" },
    { key = "L", x = 1, y = 0, label = "Right" },
  }
  local SPEEDS = {
    { mod = "", step = 10, suffix = "" },
    { mod = "SHIFT + ", step = 100, suffix = " (Fast)" },
    { mod = "CTRL + ", step = 1, suffix = " (Pixel)" },
    { mod = "CTRL + SHIFT + ", step = 300, suffix = " (Ultra Fast)" },
  }
  for _, speed in ipairs(SPEEDS) do
    for _, d in ipairs(DIRS) do
      hl.bind(
        speed.mod .. d.key,
        hl.dsp.exec_cmd("wlrctl pointer move " .. (d.x * speed.step) .. " " .. (d.y * speed.step)),
        { repeating = true, description = "Cursor " .. d.label .. speed.suffix }
      )
    end
  end

  -- !--- Mouse clicks ---
  hl.bind("SPACE", hl.dsp.exec_cmd("wlrctl pointer click left"), { description = "Left Click" })
  hl.bind("CTRL + SPACE", hl.dsp.exec_cmd("wlrctl pointer click right"), { description = "Right Click" })
  hl.bind("SHIFT + SPACE", hl.dsp.exec_cmd("wlrctl pointer click middle"), { description = "Middle Click" })

  -- stylua: ignore start
  hl.bind("A",        hl.dsp.exec_cmd("wlrctl pointer click left"),   { description = "Left Click" })
  hl.bind("S",        hl.dsp.exec_cmd("wlrctl pointer click middle"), { description = "Middle Click" })
  hl.bind("D",        hl.dsp.exec_cmd("wlrctl pointer click right"),  { description = "Right Click" })
  SubBind.run("CTRL + A", "wlrctl pointer click left",   "Left Click (Exit)")
  SubBind.run("CTRL + S", "wlrctl pointer click middle", "Middle Click (Exit)")
  SubBind.run("CTRL + D", "wlrctl pointer click right",  "Right Click (Exit)")
  -- stylua: ignore end

  -- !--- Scrolling ---
  -- NOTE: May not work in all applications. Use backups below if that is the case.
  local SCROLL_DIRS = {
    { key = "E", v = 1, h = 0, label = "Up" },
    { key = "Y", v = -1, h = 0, label = "Down" },
    { key = "COMMA", v = 1, h = 0, label = "Left" },
    { key = "PERIOD", v = -1, h = 0, label = "Right" },
  }
  local SCROLL_SPEEDS = {
    { mod = "", step = 10, suffix = "" },
    { mod = "SHIFT + ", step = 100, suffix = " (Fast)" },
    { mod = "CTRL + ", step = 1, suffix = " (Pixel)" },
  }
  for _, speed in ipairs(SCROLL_SPEEDS) do
    for _, d in ipairs(SCROLL_DIRS) do
      hl.bind(
        speed.mod .. d.key,
        hl.dsp.exec_cmd("wlrctl pointer scroll " .. (d.v * speed.step) .. " " .. (d.h * speed.step)),
        { repeating = true, description = "Scroll " .. d.label .. speed.suffix }
      )
    end
  end

  -- !--- Arrow Key Movement (backup to scrolling) ---
  -- stylua: ignore start
  hl.bind("ALT + H", hl.dsp.exec_cmd("hyprctl dispatch sendshortcut , LEFT,  activewindow"), { repeating = true, description = "Arrow Left" })
  hl.bind("ALT + J", hl.dsp.exec_cmd("hyprctl dispatch sendshortcut , DOWN,  activewindow"), { repeating = true, description = "Arrow Down" })
  hl.bind("ALT + K", hl.dsp.exec_cmd("hyprctl dispatch sendshortcut , UP,    activewindow"), { repeating = true, description = "Arrow Up" })
  hl.bind("ALT + L", hl.dsp.exec_cmd("hyprctl dispatch sendshortcut , RIGHT, activewindow"), { repeating = true, description = "Arrow Right" })
  -- stylua: ignore end

  -- !--- PageUp/PageDown (backup for fast scrolling) ---
  hl.bind(
    "CTRL + U",
    hl.dsp.exec_cmd("hyprctl dispatch sendshortcut , prior, activewindow"),
    { description = "Page Up" }
  )
  hl.bind(
    "CTRL + D",
    hl.dsp.exec_cmd("hyprctl dispatch sendshortcut , next,  activewindow"),
    { description = "Page Down" }
  )

  -- !--- Exit ---
  hl.bind("Escape", function()
    restore_cursor_config(CURSOR.defaults)
    hl.dispatch(hl.dsp.exec_cmd("pkill wl-kbptr"))
    hl.dispatch(hl.dsp.submap("reset"))
  end)
  hl.bind("catchall", hl.dsp.submap(CURSOR.name))
end)
