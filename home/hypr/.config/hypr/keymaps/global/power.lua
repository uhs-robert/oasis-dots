local Bind = require("lib.key.bind") ---@class BindLib
local Scripts = require("lib.scripts") ---@class Scripts

-- The script acts only while it holds the logind inhibitor, so unset state keeps logind's defaults.
Bind.cmd("switch:on:Lid Switch", Scripts.power .. " lid", "Lid Closed", { locked = true })
Bind.cmd("XF86PowerOff", Scripts.power .. " button", "Power Button", { locked = true })
