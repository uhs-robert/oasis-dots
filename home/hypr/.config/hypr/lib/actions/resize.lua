--- Resize actions for the Resize submap.
--- Use Resize.speeds for pre-built directional action sets at common step sizes,
--- or Resize.at(n) to create a custom set.
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


function Resize.left()  hl.dispatch(hl.dsp.window.resize({ x = -Resize.amount, y = 0,             relative = true })) end
function Resize.right() hl.dispatch(hl.dsp.window.resize({ x = Resize.amount,  y = 0,             relative = true })) end
function Resize.up()    hl.dispatch(hl.dsp.window.resize({ x = 0,              y = -Resize.amount, relative = true })) end
function Resize.down()  hl.dispatch(hl.dsp.window.resize({ x = 0,              y = Resize.amount,  relative = true })) end

--- @param amount number
function Resize.set_amount(amount) Resize.amount = amount end

--- Return a ResizeActions set that moves by `amount` pixels.
--- @param amount number
--- @return ResizeActions
function Resize.at(amount)
  return {
    left  = function() hl.dispatch(hl.dsp.window.resize({ x = -amount, y = 0,       relative = true })) end,
    right = function() hl.dispatch(hl.dsp.window.resize({ x = amount,  y = 0,       relative = true })) end,
    up    = function() hl.dispatch(hl.dsp.window.resize({ x = 0,       y = -amount, relative = true })) end,
    down  = function() hl.dispatch(hl.dsp.window.resize({ x = 0,       y = amount,  relative = true })) end,
  }
end


--- Reset window size by toggling float twice (forces layout recalculation).
function Resize.reset()
  hl.dispatch(hl.dsp.window.float({ action = "toggle" }))
  hl.dispatch(hl.dsp.window.float({ action = "toggle" }))
end

return Resize
