--- Non-blocking prompt helper.  Runs a dmenu-style prompt via exec_cmd so the
--- compositor thread is never blocked waiting for user input.  The result is
--- written to a state file by the shell, then read back inside a global callback
--- that is dispatched by hyprctl once the prompt exits.

local Config = require("config") ---@class Config
local Cmd = require("lib.actions.cmd") ---@class Cmd
local Scripts = require("lib.scripts") ---@class Scripts

--- @class Prompt
local Prompt = {}

local callbacks = {}
local counter = 0

---@param s string
---@return string
local function shell_quote(s) return "'" .. s:gsub("'", "'\\''") .. "'" end

---Build the shell command string using the configured dmenu invocation.
---@param label string  prompt label shown to the user
---@return string
local function build_cmd(label) return Config.app.dmenu_cmd .. " -p " .. string.format("%q", label) end

---Register a callback under a fresh id and return the id with its file paths.
---@param callback fun(result: string|nil)
---@return string id, table paths
local function new_request(callback)
  counter = counter + 1
  local id = os.time() .. "-" .. counter
  local base = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/hypr-prompt-" .. id
  local paths = { result = base .. ".out", input = base .. ".in", spec = base .. ".json" }
  callbacks[id] = { callback = callback, paths = paths }
  return id, paths
end

---Shell snippet that tells Hyprland the prompt with this id has answered.
---@param id string
---@return string
local function answer_cmd(id) return "hyprctl eval " .. shell_quote('_hv_prompt_cb("' .. id .. '")') end

---Global entry point for the shell side; a stale or repeated id is ignored.
---@param id string
_G._hv_prompt_cb = function(id)
  local entry = callbacks[id]
  if not entry then return end
  callbacks[id] = nil
  local f = io.open(entry.paths.result, "r")
  local result = ""
  if f then
    result = f:read("*a"):gsub("%s+$", "")
    f:close()
  end
  for _, path in pairs(entry.paths) do
    os.remove(path)
  end
  entry.callback(result ~= "" and result or nil)
end

---Show a dmenu-style text-input prompt without blocking the compositor.
---`callback` is called once with the entered string, or nil if cancelled.
---@param label    string
---@param callback fun(result: string|nil)
function Prompt.async(label, callback)
  local id, paths = new_request(callback)
  local cmd = build_cmd(label) .. " > " .. shell_quote(paths.result) .. " ; " .. answer_cmd(id)
  Cmd.run(cmd)()
end

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
  local id, paths = new_request(callback)
  local f = io.open(paths.input, "w")
  if f then
    f:write(table.concat(choices, "\n"))
    f:close()
  end
  f = io.open(paths.spec, "w")
  if f then
    local quoted = {}
    for i, c in ipairs(choices) do
      quoted[i] = json_str(c)
    end
    f:write(
      '{"id":'
        .. json_str(id)
        .. ',"label":'
        .. json_str(label)
        .. ',"result_path":'
        .. json_str(paths.result)
        .. ',"choices":['
        .. table.concat(quoted, ",")
        .. "]}"
    )
    f:close()
  end
  local fallback = "cat "
    .. shell_quote(paths.input)
    .. " | "
    .. build_cmd(label)
    .. " > "
    .. shell_quote(paths.result)
    .. " ; "
    .. answer_cmd(id)
  Cmd.run(Scripts.qs_picker .. " choices " .. shell_quote(fallback) .. " " .. shell_quote(paths.spec))()
end

return Prompt
