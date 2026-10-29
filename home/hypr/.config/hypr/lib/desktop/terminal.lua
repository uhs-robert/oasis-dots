--- Terminal launchers: the configured terminal (`Config.app.term_cmd`), a command in it, or the bottom-half terminal.

local Config = require("config") ---@class Config
local Hypr = require("lib.hypr") ---@class HyprLib

local TERM_CMD = Config.app.term_cmd

--- @class Terminal
local Terminal = {}

--- Return an action that opens a new terminal window.
--- @return fun()
Terminal.open = function() return Hypr.exec(TERM_CMD) end

--- Return an action that runs a command in the configured terminal.
--- @param command string
--- @return fun()
Terminal.run = function(command) return Hypr.exec(TERM_CMD .. " -e " .. command) end

local BOTTOM_CLASS = "bottom-half-screen"
local PREFILL_TIMEOUT_MS = 5000
local PREFILL_SETTLE_MS = 300

--- Type text into the next window of BOTTOM_CLASS that opens, then stop listening.
--- @param text string
local function prefill_when_open(text)
  local sub
  local timeout
  local function stop()
    if sub then sub:remove() end
    if timeout then timeout:set_enabled(false) end
    sub = nil
  end
  sub = hl.on("window.open", function(w)
    if not sub or not w or w.class ~= BOTTOM_CLASS then return end
    stop()
    local address = w.address
    hl.timer(function()
      hl.dispatch(hl.dsp.focus({ window = "address:" .. address }))
      local escaped = text:gsub("'", "'\\''")
      hl.exec_cmd("wtype -- '" .. escaped .. "'")
    end, { timeout = PREFILL_SETTLE_MS, type = "oneshot" })
  end)
  timeout = hl.timer(stop, { timeout = PREFILL_TIMEOUT_MS, type = "oneshot" })
end

--- Return an action that runs a command in a terminal tagged "bottom-half-screen",
--- (see config/rules window_rule "bottom-half-screen").
--- If no command given, just opens the terminal with that class.
--- @param command string|nil
--- @param prefill boolean|nil If true, load command into the shell prompt instead of running it.
--- @return fun()
Terminal.bottom = function(command, prefill)
  local cmd = TERM_CMD .. " --class " .. BOTTOM_CLASS
  if command and not prefill then return Hypr.exec(cmd .. " -e " .. command) end
  return function()
    if command then prefill_when_open(command) end
    hl.dispatch(hl.dsp.exec_cmd(cmd))
  end
end

return Terminal
