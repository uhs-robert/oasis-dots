--- Screenshot submap
--- Each bind runs a screenshot/record command

local Config = require("config") ---@class Config
local Scripts = require("lib.scripts") ---@class Scripts
local Submap = require("lib.key.submap") ---@class Submap
local Apps = require("lib.actions.apps") ---@class Apps

--- Return an action that runs the screenshot script with an optional subcommand flag.
--- @param arg? string  subcommand passed as `--arg` (e.g. "freeze", "screen", "window")
--- @return fun()
local screenshot = function(arg) return Apps.open(Scripts.screenshot .. (arg and " --" .. arg or "")) end

Submap.define({
  name = "Screenshot",
  desc = "+Screenshot",
  enter = Config.leader .. " + I",

  escape = "reset",
  catchall = "reset",

  -- stylua: ignore
  binds = {
    { "SLASH",     screenshot(),                 "Print Options" },
    { "I",         screenshot("freeze"),         "Screenshot Frozen Region" },
    { "SHIFT + I", screenshot("record-region"),  "Record Region" },
    { "S",         screenshot("screen"),         "Screenshot Screen" },
    { "SHIFT + S", screenshot("record-screen"),  "Record Screen" },
    { "W",         screenshot("window"),         "Screenshot Window" },
    { "SHIFT + W", screenshot("record-window"),  "Record Window" },
    { "R",         screenshot("record-focused"), "Record Focused Window" },
    { "T",         screenshot("text"),           "OCR Text in Region" },
    { "P",         screenshot("pixel"),          "Color Picker" },
  },
}).setup()
