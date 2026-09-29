--- Non-blocking prompt helper.  Runs a dmenu-style prompt via exec_cmd so the
--- compositor thread is never blocked waiting for user input.  The result is
--- written to a state file by the shell, then read back inside a global callback
--- that is dispatched by hyprctl once the prompt exits.

local Config = require("config") ---@class Config
local Hypr = require("lib.hypr") ---@class HyprLib
local Cmd = require("lib.actions.cmd") ---@class Cmd
local Scripts = require("lib.scripts") ---@class Scripts

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

---@param s string
---@return string
local function shell_quote(s) return "'" .. s:gsub("'", "'\\''") .. "'" end

---@param s string
---@return string
local function json_str(s)
  local escaped = s:gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end)
  return '"' .. escaped .. '"'
end

---Show a selection picker without blocking the compositor: the Quickshell "choices" picker when the bar answers, else dmenu.
---`callback` is called once with the chosen string, or nil if cancelled.
---@param label    string
---@param choices  string[]
---@param callback fun(result: string|nil)
function Prompt.select(label, choices, callback)
  local runtime = os.getenv("XDG_RUNTIME_DIR") or "/tmp"
  local input_file = runtime .. "/hypr-prompt-choices"
  local spec_file = input_file .. ".json"
  local f = io.open(input_file, "w")
  if f then
    f:write(table.concat(choices, "\n"))
    f:close()
  end
  f = io.open(spec_file, "w")
  if f then
    local quoted = {}
    for i, c in ipairs(choices) do
      quoted[i] = json_str(c)
    end
    f:write(
      '{"label":'
        .. json_str(label)
        .. ',"result_path":'
        .. json_str(STATE_FILE)
        .. ',"choices":['
        .. table.concat(quoted, ",")
        .. "]}"
    )
    f:close()
  end
  install_cb(callback)
  local fallback = "cat "
    .. shell_quote(input_file)
    .. " | "
    .. build_cmd(label)
    .. " > "
    .. STATE_FILE
    .. " ; hyprctl dispatch '_hv_prompt_cb()'"
  Cmd.run(Scripts.qs_picker .. " choices " .. shell_quote(fallback) .. " " .. shell_quote(spec_file))()
end

return Prompt
