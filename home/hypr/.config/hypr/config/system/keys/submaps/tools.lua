-- home/hypr/.config/hypr/config/system/keys/submaps/tools.lua

local SubBind = require("lib.submap_bind") ---@class SubBind
local SUBMAP = require("config.system.keys.submap").map

--- Screenshot
hl.define_submap(SUBMAP.screenshot.name, function()
  local SS = "~/.config/hypr/scripts/screenshot.sh"
    -- stylua: ignore start
  --
    -- !--- Screenshot modes ---
    SubBind.run("SLASH",     SS,                        "Print Options")
    SubBind.run("I",         SS .. " --freeze",         "Screenshot Frozen Region")
    SubBind.run("SHIFT + I", SS .. " --record-region",  "Record Region")
    SubBind.run("S",         SS .. " --screen",         "Screenshot Screen")
    SubBind.run("SHIFT + S", SS .. " --record-screen",  "Record Screen")
    SubBind.run("W",         SS .. " --window",         "Screenshot Window")
    SubBind.run("SHIFT + W", SS .. " --record-window",  "Record Window")
    SubBind.run("R",         SS .. " --record-focused", "Record Focused Window")

    -- !--- Tools ---
    SubBind.run("T", SS .. " --text",  "OCR Text in Region")
    SubBind.run("P", SS .. " --pixel", "Color Picker")
  -- stylua: ignore end

  SubBind.bind_exits()
end)
