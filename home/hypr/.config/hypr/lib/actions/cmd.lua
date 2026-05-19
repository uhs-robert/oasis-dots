--- Command runner.
--- All actions dispatch a command.

local Config = require("config") ---@class Config

local TERM = Config.app.term

--- @class Cmd
local Cmd = {}

--- Return an action that runs a shell command.
--- @param cmd string
--- @return fun()
Cmd.run = function(cmd)
  return function() hl.dispatch(hl.dsp.exec_cmd(cmd)) end
end

--- Return an action that runs a command in the configured terminal.
--- @param command string
--- @return fun()
Cmd.term = function(command) return Cmd.run(TERM .. " -e " .. command) end

return Cmd
