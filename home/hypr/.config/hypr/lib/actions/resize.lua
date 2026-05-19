--- Resize actions for the Resize submap.
--- Use Resize.at(n) to create a directional action set at a custom step size.

--- @class Resize
local Resize = {}

--- Default step size used by the bare directional functions.
--- @type number
Resize.amount = 10

--- @class ResizeActions
--- @field left  fun()
--- @field right fun()
--- @field up    fun()
--- @field down  fun()

--- Return a ResizeActions set that moves by `amount` pixels.
--- @param amount number
--- @return ResizeActions
Resize.at = function(amount)
  return {
    left = function() hl.dispatch(hl.dsp.window.resize({ x = -amount, y = 0, relative = true })) end,
    right = function() hl.dispatch(hl.dsp.window.resize({ x = amount, y = 0, relative = true })) end,
    up = function() hl.dispatch(hl.dsp.window.resize({ x = 0, y = -amount, relative = true })) end,
    down = function() hl.dispatch(hl.dsp.window.resize({ x = 0, y = amount, relative = true })) end,
  }
end

local DEFAULTS = Resize.at(Resize.amount)
Resize.left = DEFAULTS.left
Resize.right = DEFAULTS.right
Resize.up = DEFAULTS.up
Resize.down = DEFAULTS.down

--- Reset window size by toggling float twice (forces layout recalculation).
Resize.reset = function()
  hl.dispatch(hl.dsp.window.float({ action = "toggle" }))
  hl.dispatch(hl.dsp.window.float({ action = "toggle" }))
end

return Resize
