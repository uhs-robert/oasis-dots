--- Matches window rounding to the screen frame Quickshell draws round the usable area, and restores it when the
--- frame goes. Self-contained (no requires), so the shadow harness can dofile it on its own.

local FRAME_NAMESPACE = "quickshell-frame"
local WATCHDOG_MS = 2000
-- About 6 s without a frame layer: longer than a Quickshell reload takes to map the new one.
local MISSES_BEFORE_RESTORE = 3

-- The rounding in force before a frame took over, nil while none does. Held here rather than in Quickshell, so a
-- Quickshell restart never mistakes the frame's rounding for the user's own.
local saved_rounding = nil
local missed_checks = 0
local watchdog = nil

--- The smallest gap between tiled windows and the usable area's edge.
--- @return number
local function gaps_out()
  local gaps = hl.get_config("general.gaps_out")
  if type(gaps) == "number" then return gaps end
  local smallest = nil
  if type(gaps) == "table" then
    for _, side in pairs(gaps) do
      if type(side) == "number" and (smallest == nil or side < smallest) then smallest = side end
    end
  end
  return smallest or 0
end

local function frame_mapped()
  for _, layer in ipairs(hl.get_layers({ namespace = FRAME_NAMESPACE }) or {}) do
    if layer.mapped then return true end
  end
  return false
end

local function restore()
  if watchdog then watchdog:set_enabled(false) end
  if saved_rounding == nil then return end
  hl.config({ decoration = { rounding = saved_rounding } })
  saved_rounding = nil
end

-- Quickshell sends -1 when the frame goes, but a crashed or quit Quickshell sends nothing, so the frame's layer
-- going missing restores too.
local function check_frame()
  if frame_mapped() then
    missed_checks = 0
    return
  end
  missed_checks = missed_checks + 1
  if missed_checks >= MISSES_BEFORE_RESTORE then restore() end
end

--- Rounds windows to sit concentric with a frame corner of `radius`, or restores the user's rounding for -1.
--- @param radius number
local function set_rounding(radius)
  radius = tonumber(radius) or -1
  if radius < 0 then
    restore()
    return
  end
  if saved_rounding == nil then saved_rounding = hl.get_config("decoration.rounding") end
  -- Tiled windows sit gaps_out inside the frame's hole, so a corner of radius - gaps_out keeps the gap even round it.
  hl.config({ decoration = { rounding = math.max(0, math.floor(radius - gaps_out())) } })
  missed_checks = 0
  if watchdog then
    watchdog:set_enabled(true)
  else
    watchdog = hl.timer(check_frame, { timeout = WATCHDOG_MS, type = "repeat" })
  end
end

-- Global functions which are accessible externally via `hyprctl dispatch "ScreenFrame"`
_G.ScreenFrame = {
  set_rounding = function(radius)
    set_rounding(radius)

    return hl.dsp.no_op()
  end,
}
