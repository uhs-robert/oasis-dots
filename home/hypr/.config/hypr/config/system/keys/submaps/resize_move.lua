-- home/hypr/.config/hypr/keys/submaps/resize_move.lua

local Bind = require("lib.submap_bind")
local SUBMAP = require("config.system.keys.submap").map

--- Bind HJKL at four speed tiers with repeat.
--- @param action fun(opts: {x: number, y: number})
--- @param desc string Description prefix
local function set_speed_dir_binds(action, desc)
  -- FIX: Invalid size
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
        action({ x = d.x * speed.step, y = d.y * speed.step }),
        { repeating = true, description = desc .. " " .. d.label .. speed.suffix }
      )
    end
  end
end

local function reset_float()
  hl.dispatch(hl.dsp.window.float({ action = "toggle" }))
  hl.dispatch(hl.dsp.window.float({ action = "toggle" }))
end

--- Resize
hl.define_submap(SUBMAP.resize.name, function()
  set_speed_dir_binds(hl.dsp.window.resize, SUBMAP.resize.name)
  hl.bind("EQUAL", reset_float, { description = "Reset Size" })

  -- !--- Modes ---
  hl.bind("F", hl.dsp.window.float(), { action = "toggle", description = "Toggle Floating" })
  hl.bind("P", hl.dsp.window.pseudo(), { description = "Toggle Pseudo (dwindle)" })
  hl.bind("S", hl.dsp.layout("togglesplit"), { description = "Toggle Split (dwindle)" })

  -- !--- Switch to other submaps ---
  Bind.bind(SUBMAP.move)
  Bind.bind(SUBMAP.windows)

  Bind.set_escape(SUBMAP.resize)
end)

--- Move
hl.define_submap(SUBMAP.move.name, function()
  -- FIX: Does nothing
  set_speed_dir_binds(hl.dsp.window.move, SUBMAP.move.name)
  hl.bind("EQUAL", reset_float, { description = "Reset Position" })

  -- !--- Switch to other submaps ---
  Bind.bind(SUBMAP.resize)
  Bind.bind(SUBMAP.windows)

  Bind.set_escape(SUBMAP.move)
end)
