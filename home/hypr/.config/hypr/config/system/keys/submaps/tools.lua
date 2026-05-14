-- home/hypr/.config/hypr/keys/submaps/tools.lua

local Bind = require("lib.submap_bind")
local SUBMAP = require("config.system.keys.submap").map

--- Screenshot
hl.define_submap(SUBMAP.screenshot.name, function()
  local SS = "~/.config/hypr/scripts/screenshot.sh"
    -- stylua: ignore start
  --
    -- !--- Screenshot modes ---
    Bind.run("SLASH",     SS,                        "Print Options")
    Bind.run("I",         SS .. " --freeze",         "Screenshot Frozen Region")
    Bind.run("SHIFT + I", SS .. " --record-region",  "Record Region")
    Bind.run("S",         SS .. " --screen",         "Screenshot Screen")
    Bind.run("SHIFT + S", SS .. " --record-screen",  "Record Screen")
    Bind.run("W",         SS .. " --window",         "Screenshot Window")
    Bind.run("SHIFT + W", SS .. " --record-window",  "Record Window")
    Bind.run("R",         SS .. " --record-focused", "Record Focused Window")

    -- !--- Tools ---
    Bind.run("T", SS .. " --text",  "OCR Text in Region")
    Bind.run("P", SS .. " --pixel", "Color Picker")
  -- stylua: ignore end

  Bind.set_escape(SUBMAP.screenshot)
end)
