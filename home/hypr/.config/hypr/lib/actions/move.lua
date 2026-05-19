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

--- Return a MoveActions set that moves by `amount` pixels.
--- @param amount number
--- @return MoveActions
Move.at = function(amount)
  return {
    left = function() hl.dispatch(hl.dsp.window.move({ x = -amount, y = 0, relative = true })) end,
    right = function() hl.dispatch(hl.dsp.window.move({ x = amount, y = 0, relative = true })) end,
    up = function() hl.dispatch(hl.dsp.window.move({ x = 0, y = -amount, relative = true })) end,
    down = function() hl.dispatch(hl.dsp.window.move({ x = 0, y = amount, relative = true })) end,
  }
end

local DEFAULTS = Move.at(Move.amount)
Move.left = DEFAULTS.left
Move.right = DEFAULTS.right
Move.up = DEFAULTS.up
Move.down = DEFAULTS.down

return Move
