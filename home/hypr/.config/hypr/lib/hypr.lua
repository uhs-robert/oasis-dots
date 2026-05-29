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

--- Run cmd, then dispatch a Lua expr via hyprctl once it exits.
--- This acts as a shell --block which allows a shell command to be awaited.
--- @param cmd string            Shell command to run
--- @param dispatch_expr string  hl.dsp.* Lua expression, e.g. 'hl.dsp.submap("Cursor")'
--- @return fun()
function Hypr.cmd_then_dispatch(cmd, dispatch_expr)
  return function() hl.dispatch(hl.dsp.exec_cmd(cmd .. " ; hyprctl dispatch '" .. dispatch_expr .. "'")) end
end

return Hypr
