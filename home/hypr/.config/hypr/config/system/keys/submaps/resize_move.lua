-- home/hypr/.config/hypr/config/system/keys/submaps/resize_move.lua

local SubBind = require("lib.submap_bind") ---@class SubBind
local SUBMAP = require("config.system.keys.submap").map

--- Bind HJKL at four speed tiers with repeat.
--- @param action fun(opts: {x: number, y: number})
--- @param desc string Description prefix
local function set_speed_dir_binds(action, desc)
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
        action({ x = d.x * speed.step, y = d.y * speed.step, relative = true }),
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
  SubBind.swap_to(SUBMAP.move, { key = "M" })
  SubBind.swap_to(SUBMAP.windows, { key = "W" })

  SubBind.bind_exits({ swallow_mispress = true })
end)

--- Move
hl.define_submap(SUBMAP.move.name, function()
  set_speed_dir_binds(hl.dsp.window.move, SUBMAP.move.name)
  hl.bind("EQUAL", reset_float, { description = "Reset Position" })

  -- !--- Switch to other submaps ---
  SubBind.swap_to(SUBMAP.resize, { key = "R" })
  SubBind.swap_to(SUBMAP.windows, { key = "W" })

  SubBind.bind_exits({ swallow_mispress = true })
end)
