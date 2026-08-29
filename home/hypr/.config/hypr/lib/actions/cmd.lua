--- Command runner.
--- All actions dispatch a command.

local Config = require("config") ---@class Config

local TERM_CMD = Config.app.term_cmd

--- @class Cmd
local Cmd = {}

--- Return an action that runs a shell command.
--- @param cmd string
--- @return fun()
Cmd.run = function(cmd)
  return function() hl.dispatch(hl.dsp.exec_cmd(cmd)) end
end

--- Return an action that opens a new terminal window.
--- @return fun()
Cmd.open_term = function() return Cmd.run(TERM_CMD) end

--- Return an action that runs a command in the configured terminal.
--- @param command string
--- @return fun()
Cmd.term = function(command) return Cmd.run(TERM_CMD .. " -e " .. command) end

--- Return an action that runs a command in a terminal tagged "bottom-half-screen",
--- (see config/rules window_rule "bottom-half-screen").
--- If no command given, just opens the terminal with that class.
--- @param command string|nil
--- @return fun()
Cmd.bottom_terminal = function(command)
  local cmd = TERM_CMD .. " --class bottom-half-screen"
  if command then cmd = cmd .. " -e " .. command end
  return Cmd.run(cmd)
end

return Cmd
