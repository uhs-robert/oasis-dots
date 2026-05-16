--- Go submap actions.
--- Action factories that return functions suitable for use as bind actions.
--- Submap exit is handled automatically via catchall = "reset" (oneshot).

local Window = require("lib.window")

--- @class Go
local Go = {}

--- Return an action that runs a shell command.
--- @param cmd string
--- @return fun()
function Go.run(cmd)
  return function() hl.dispatch(hl.dsp.exec_cmd(cmd)) end
end

--- Return an action that dispatches a Hyprland API call.
--- @param fn fun()
--- @return fun()
function Go.exec(fn)
  return function() hl.dispatch(fn) end
end

--- Return an action that focuses an existing window or launches the app.
--- @param opts { program: string, class?: string, title?: string, exclude_title?: string, cmd?: string }
--- @return fun()
function Go.focus_or_launch(opts)
  return function() Window.focus_or_launch(opts) end
end

return Go
