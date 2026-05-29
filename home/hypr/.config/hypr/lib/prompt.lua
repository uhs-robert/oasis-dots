--- Non-blocking prompt helper.  Runs a dmenu-style prompt via exec_cmd so the
--- compositor thread is never blocked waiting for user input.  The result is
--- written to a state file by the shell, then read back inside a global callback
--- that is dispatched by hyprctl once the prompt exits.

local Config = require("config") ---@class Config
local Hypr = require("lib.hypr") ---@class HyprLib

local STATE_FILE = "/tmp/hypr-prompt-result"

--- @class Prompt
local Prompt = {}

---Build the shell command string using the configured dmenu invocation.
---@param label string  prompt label shown to the user
---@return string
local function build_cmd(label) return Config.app.dmenu_cmd .. " -p " .. string.format("%q", label) end

---Shared callback installer + result reader.
---@param callback fun(result: string|nil)
local function install_cb(callback)
  _G._hv_prompt_cb = function()
    local f = io.open(STATE_FILE, "r")
    local result = f and f:read("*a"):gsub("%s+$", "") or ""
    if f then
      f:close()
      os.remove(STATE_FILE)
    end
    _G._hv_prompt_cb = nil
    callback(result ~= "" and result or nil)
  end
end

---Show a dmenu-style text-input prompt without blocking the compositor.
---`callback` is called once with the entered string, or nil if cancelled.
---@param label    string
---@param callback fun(result: string|nil)
function Prompt.async(label, callback)
  install_cb(callback)
  local cmd = build_cmd(label) .. " > " .. STATE_FILE
  Hypr.cmd_then_dispatch(cmd, "_hv_prompt_cb()")()
end

---Show a dmenu-style selection picker without blocking the compositor.
---`callback` is called once with the chosen string, or nil if cancelled.
---@param label    string
---@param choices  string[]
---@param callback fun(result: string|nil)
function Prompt.select(label, choices, callback)
  local input_file = "/tmp/hypr-prompt-choices"
  local f = io.open(input_file, "w")
  if f then
    f:write(table.concat(choices, "\n"))
    f:close()
  end
  install_cb(callback)
  local cmd = "cat " .. input_file .. " | " .. build_cmd(label) .. " > " .. STATE_FILE
  Hypr.cmd_then_dispatch(cmd, "_hv_prompt_cb()")()
end

return Prompt
