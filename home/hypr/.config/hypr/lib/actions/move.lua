--- Move actions for the Move submap.
--- Use Move.at(n) to create a directional action set at a given pixel step size.

--- @class Move
local Move = {}

--- Default step size used by the bare directional functions.
--- @type number
Move.amount = 10

--- @class MoveActions
--- @field left  fun()
--- @field right fun()
--- @field up    fun()
--- @field down  fun()

function Move.left()  hl.dispatch(hl.dsp.window.move({ x = -Move.amount, y = 0,            relative = true })) end
function Move.right() hl.dispatch(hl.dsp.window.move({ x = Move.amount,  y = 0,            relative = true })) end
function Move.up()    hl.dispatch(hl.dsp.window.move({ x = 0,            y = -Move.amount, relative = true })) end
function Move.down()  hl.dispatch(hl.dsp.window.move({ x = 0,            y = Move.amount,  relative = true })) end

--- @param amount number
function Move.set_amount(amount) Move.amount = amount end

--- Return a MoveActions set that moves by `amount` pixels.
--- @param amount number
--- @return MoveActions
function Move.at(amount)
  return {
    left  = function() hl.dispatch(hl.dsp.window.move({ x = -amount, y = 0,       relative = true })) end,
    right = function() hl.dispatch(hl.dsp.window.move({ x = amount,  y = 0,       relative = true })) end,
    up    = function() hl.dispatch(hl.dsp.window.move({ x = 0,       y = -amount, relative = true })) end,
    down  = function() hl.dispatch(hl.dsp.window.move({ x = 0,       y = amount,  relative = true })) end,
  }
end

return Move
