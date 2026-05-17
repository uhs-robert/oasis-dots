--- Key binding helpers built on top of hl.bind.

local Config = require("config")

--- @class BindLib
local Bind = {
  leader = Config.leader,
}

--- @param value string|string[]  Multiple keys produce one hl.bind call each, all wired to the same action
--- @return string[]
local function as_list(value)
  if type(value) == "table" then return value end

  return { value }
end

--- @param prefix string  Leader key string, e.g. "SUPER"
--- @param key    string  Raw key to bind, e.g. "H"
--- @return string        Combined string, e.g. "SUPER + H"
local function with_prefix(prefix, key)
  if not prefix or prefix == "" then return key end

  return prefix .. " + " .. key
end

--- Register one or more keys to a single action.
--- @param keys   string|string[]         Key string(s); multiples register the same action for each
--- @param action HL.Dispatcher|function  Dispatcher or Lua function
--- @param desc   string|HL.BindOptions|nil  Description string, or opts table (desc is then omitted)
--- @param opts   HL.BindOptions|nil
function Bind.key(keys, action, desc, opts)
  if type(desc) == "table" and opts == nil then
    opts = desc
    desc = nil
  end

  opts = opts or {}

  if desc then
    opts.desc = desc --[[@as string]]
  end

  for _, key in ipairs(as_list(keys)) do
    hl.bind(key, action, opts)
  end
end

--- Like Bind.key but automatically prepends Bind.leader to every key.
--- @param keys   string|string[]
--- @param action HL.Dispatcher|function
--- @param desc   string|HL.BindOptions|nil
--- @param opts   HL.BindOptions|nil
function Bind.leader_key(keys, action, desc, opts)
  local prefixed = {}
  for _, k in ipairs(as_list(keys)) do
    table.insert(prefixed, with_prefix(Bind.leader, k))
  end
  Bind.key(prefixed, action, desc, opts)
end

--- Register a key that runs a shell command.
--- @param keys string|string[]
--- @param cmd  string
--- @param desc string|HL.BindOptions|nil
--- @param opts HL.BindOptions|nil
function Bind.cmd(keys, cmd, desc, opts) Bind.key(keys, hl.dsp.exec_cmd(cmd), desc, opts) end

--- Like Bind.cmd but prepends Bind.leader.
--- @param keys string|string[]
--- @param cmd  string
--- @param desc string|HL.BindOptions|nil
--- @param opts HL.BindOptions|nil
function Bind.leader_cmd(keys, cmd, desc, opts) Bind.leader_key(keys, hl.dsp.exec_cmd(cmd), desc, opts) end

--- Register multiple binds from a row table.
--- Each row is { keys, action, desc, opts? } where opts is a HL.BindOptions table.
--- @param rows     { [1]: string|string[], [2]: any, [3]: string, [4]: HL.BindOptions|nil }[]
--- @param defaults HL.BindOptions|nil  Opts applied to every row; row[4] takes precedence
function Bind.keys(rows, defaults)
  for _, row in ipairs(rows or {}) do
    local opts = {}
    for k, v in pairs(defaults or {}) do
      opts[k] = v
    end
    for k, v in pairs(row[4] or {}) do
      opts[k] = v
    end
    Bind.key(row[1], row[2], row[3], opts)
  end
end

return Bind
