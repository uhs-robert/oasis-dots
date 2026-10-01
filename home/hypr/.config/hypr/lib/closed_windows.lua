--- Remembers windows closed by keybinds so the last one can be reopened.

local Scripts = require("lib.scripts") --- @class Scripts

local MAX_ENTRIES = 20
local KITTY_CMD = "kitty --single-instance"
local STATE_DIR = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/hypr-closed-windows"

--- @class ClosedEntry
--- @field cmd string
--- @field cmd_file string|nil  written by an async capture; overrides cmd when present
--- @field rules table<string, string|number|boolean>

--- @class ClosedWindows
local Closed = {}

--- @type table<string, ClosedEntry>
local pending = {}
--- @type ClosedEntry[]
local stack = {}

--- @param s string
--- @return string
local function quote(s) return "'" .. s:gsub("'", "'\\''") .. "'" end

--- @param path string
--- @return string|nil
local function read_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local content = f:read("a")
  f:close()
  return content
end

--- Shell-quoted command line of a running process.
--- @param pid integer
--- @return string|nil
local function process_cmd(pid)
  local args = {}
  for arg in (read_file("/proc/" .. pid .. "/cmdline") or ""):gmatch("[^\0]+") do
    args[#args + 1] = quote(arg)
  end
  if #args == 0 then return nil end
  return table.concat(args, " ")
end

--- Record a window about to close; returns a shell command when the capture must run async.
--- @param w HL.Window
--- @return string|nil
local function snapshot(w)
  local rules = {}
  if w.workspace then rules.workspace = w.workspace.id > 0 and w.workspace.id or w.workspace.name end
  if w.floating then
    rules.float = true
    rules.size = w.size.x .. " " .. w.size.y
  end

  -- Kitty shares one pid across windows; it must be asked off the compositor thread or both hang.
  local comm = (read_file("/proc/" .. w.pid .. "/comm") or ""):gsub("%s+$", "")
  if comm == "kitty" then
    local base = KITTY_CMD
    if w.class ~= "kitty" then base = base .. " --class " .. quote(w.class) end
    local cmd_file = STATE_DIR .. "/" .. w.address
    pending[w.address] = { cmd = base, cmd_file = cmd_file, rules = rules }
    local focused = w.address == (hl.get_active_window() or {}).address and "1" or "0"
    local args = { tostring(w.pid), quote(w.class), quote(w.title), focused, quote(base), quote(cmd_file) }
    return Scripts.kitty_window_cmd .. " " .. table.concat(args, " ")
  end

  local cmd = process_cmd(w.pid)
  if cmd then pending[w.address] = { cmd = cmd, rules = rules } end
end

--- Close windows, remembering each so it can be restored.
--- @param windows HL.Window[]
--- @param action "close"|"kill"|"sigkill"
function Closed.close(windows, action)
  local captures, closes = {}, {}
  for _, w in ipairs(windows) do
    if w.pid and w.pid > 0 then captures[#captures + 1] = snapshot(w) end
  end

  if #captures == 0 then
    for _, w in ipairs(windows) do
      if action == "sigkill" then
        os.execute("kill -9 " .. tostring(w.pid))
      else
        hl.dispatch(hl.dsp.window[action]({ window = "address:" .. w.address }))
      end
    end
    return
  end

  for _, w in ipairs(windows) do
    closes[#closes + 1] = action == "sigkill" and ("kill -9 " .. tostring(w.pid))
      or string.format([[hyprctl dispatch 'hl.dsp.window.%s({ window = "address:%s" })']], action, w.address)
  end
  hl.dispatch(hl.dsp.exec_cmd(table.concat(captures, "; ") .. "; " .. table.concat(closes, "; ")))
end

--- Reopen the most recently closed window.
function Closed.restore()
  local entry = table.remove(stack)
  if not entry then return end
  local cmd = entry.cmd
  if entry.cmd_file then
    local saved = (read_file(entry.cmd_file) or ""):gsub("%s+$", "")
    os.remove(entry.cmd_file)
    if saved ~= "" then cmd = saved end
  end
  hl.dispatch(hl.dsp.exec_cmd(cmd, entry.rules))
end

hl.on("window.close", function(w)
  local entry = w and pending[w.address]
  if not entry then return end
  pending[w.address] = nil
  stack[#stack + 1] = entry
  if #stack > MAX_ENTRIES then table.remove(stack, 1) end
end)

--- Close windows by address; matches HyprVim's close_handler signature.
--- @param addresses string[]
--- @param kill boolean
function Closed.close_addresses(addresses, kill)
  local windows = {}
  for _, address in ipairs(addresses) do
    windows[#windows + 1] = hl.get_window("address:" .. address)
  end
  Closed.close(windows, kill and "kill" or "close")
end

return Closed
