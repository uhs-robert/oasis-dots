--- Builds a `run` for an action that calls a performer in another module when it fires. The performers read Config
--- and the session, so requiring them while a defs file loads would break the headless load that checks the ids.

--- @class Defer
local Defer = {}

--- Each key press, `require(module)[name](...)` builds a closure and the closure runs.
--- @param module string
--- @param name   string
--- @param ...    any     Fixed arguments for the builder
--- @return fun()
function Defer.call(module, name, ...)
  local fixed = { ... }
  return function() require(module)[name](table.unpack(fixed))() end
end

return Defer
