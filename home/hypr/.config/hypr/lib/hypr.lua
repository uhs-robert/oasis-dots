--- Wrappers for the hl global: dispatch, eval, and related action factories.

--- @class HyprLib
local Hypr = {}

--- Wrap a pre-built dispatcher object into a deferred action.
--- @param dispatcher any  hl.dsp.* object
--- @return fun()
function Hypr.dispatch(dispatcher)
  return function() hl.dispatch(dispatcher) end
end

--- Deferred exec_cmd action.
--- @param cmd string
--- @return fun()
function Hypr.exec(cmd) return Hypr.dispatch(hl.dsp.exec_cmd(cmd)) end

--- Deferred send_shortcut action (no modifiers).
--- @param key string  e.g. "LEFT", "prior", "next"
--- @return fun()
function Hypr.send(key) return Hypr.dispatch(hl.dsp.send_shortcut({ mods = "", key = key })) end

return Hypr
