--- App launcher actions for the Applications submap.
--- All actions dispatch a command or focus/launch a window.
--- Submap exit is handled automatically via catchall = "reset" (oneshot).

local Window = require("lib.window")

--- @class Apps
local Apps = {}

--- Return an action that runs a shell command.
--- @param cmd string
--- @return fun()
function Apps.run(cmd)
  return function() hl.dispatch(hl.dsp.exec_cmd(cmd)) end
end

--- Return an action that focuses an existing window or launches the app.
--- @param opts { program: string, class?: string, title?: string, exclude_title?: string, cmd?: string }
--- @return fun()
function Apps.focus_or_launch(opts)
  return function() Window.focus_or_launch(opts) end
end

return Apps
