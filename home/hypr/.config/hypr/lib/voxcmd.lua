--- Escape bind that cancels a voxcmd recording. voxcmd arms it through `hyprctl eval` when a recording starts and
--- disarms it when the recording ends, so Escape works as usual the rest of the time.
local Bind = require("lib.key.bind") ---@class BindLib
local Scripts = require("lib.scripts") ---@class Scripts

--- @class Voxcmd
local Voxcmd = {}

--- @type fun()|nil
local remove_cancel_bind = nil

--- Bind Escape in the global map to `voxcmd cancel`; arming twice keeps one bind.
function Voxcmd.arm_cancel()
  if remove_cancel_bind then return end
  -- "Escape" rather than the usual "ESCAPE" keeps removing it from taking the submaps' Escape binds along on
  -- Hyprland before 0.57 (see Bind.temporary).
  remove_cancel_bind = Bind.temporary("Escape", hl.dsp.exec_cmd(Scripts.voxcmd_cancel), "Cancel Voice Command")
end

function Voxcmd.disarm_cancel()
  if not remove_cancel_bind then return end
  remove_cancel_bind()
  remove_cancel_bind = nil
end

return Voxcmd
