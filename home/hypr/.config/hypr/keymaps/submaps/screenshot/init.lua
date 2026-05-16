--- Screenshot submap — entered with SUPER+I.
--- Each bind runs a screenshot/record command then exits (oneshot via catchall = "reset").
--- ESCAPE exits without action.
local Config  = require("config")
local Scripts = require("lib.scripts")
local Submap  = require("lib.key.submap")
local Apps    = require("lib.actions.apps")

local SS = Scripts.screenshot

return Submap.define({
  name  = "Screenshot",
  desc  = "+Screenshot",
  enter = Config.leader .. " + I",

  escape   = "reset",
  catchall = "reset",

  -- stylua: ignore start
  binds = {
    { "SLASH",     Apps.run(SS),                       "Print Options" },
    { "I",         Apps.run(SS .. " --freeze"),         "Screenshot Frozen Region" },
    { "SHIFT + I", Apps.run(SS .. " --record-region"),  "Record Region" },
    { "S",         Apps.run(SS .. " --screen"),         "Screenshot Screen" },
    { "SHIFT + S", Apps.run(SS .. " --record-screen"),  "Record Screen" },
    { "W",         Apps.run(SS .. " --window"),         "Screenshot Window" },
    { "SHIFT + W", Apps.run(SS .. " --record-window"),  "Record Window" },
    { "R",         Apps.run(SS .. " --record-focused"), "Record Focused Window" },
    { "T",         Apps.run(SS .. " --text"),           "OCR Text in Region" },
    { "P",         Apps.run(SS .. " --pixel"),          "Color Picker" },
  },
  -- stylua: ignore end
})
