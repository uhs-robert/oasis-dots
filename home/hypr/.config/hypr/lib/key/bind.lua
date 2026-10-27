--- Key binding helpers built on top of hl.bind.

local Config = require("config")

--- @class BindLib
local Bind = {
  leader = Config.leader,
}

-- hl.unbind drops a key from every submap (hyprwm/Hyprland#15040), so handles are kept per submap
-- for Bind.unbind. Bind.unbind and Bind.submap are public API for custom/; keep their signatures stable.

--- Submap that binds are currently being registered in; "" is the global map. Set by Bind.submap.
local scope = ""

--- @type table<string, table<string, table[]>> submap -> normalized key -> bind handles
local handles = {}

--- Hyprland compares keys ignoring case and whitespace, so "SUPER + H" and "super+h" are the same bind.
--- @param key string
--- @return string
local function normalize(key) return (key:gsub("%s+", ""):lower()) end

--- @param submap string|nil
--- @return string
local function scope_name(submap)
  if submap == nil or submap == "reset" then return "" end
  return submap
end

--- True when a handle's :remove() drops only that bind (Hyprland 0.57+); older releases disable instead.
local SCOPED_REMOVE = (function()
  local version = type(hl.version) == "function" and hl.version() or nil
  if type(version) ~= "string" then return false end
  local major, minor = version:match("^(%d+)%.(%d+)")
  major, minor = tonumber(major), tonumber(minor)
  if not major then return false end
  return major > 0 or minor >= 57
end)()

--- @param handle table  Handle returned by hl.bind
local function remove_handle(handle)
  if SCOPED_REMOVE then
    handle:remove()
  else
    handle:set_enabled(false)
  end
end

--- @param key    string
--- @param handle table|nil  Handle returned by hl.bind
local function track(key, handle)
  if type(handle) ~= "table" and type(handle) ~= "userdata" then return end
  local keys = handles[scope] or {}
  handles[scope] = keys
  local name = normalize(key)
  keys[name] = keys[name] or {}
  table.insert(keys[name], handle)
end

--- Action ids by the function a bind runs, so a check can tell a bind that performs an action from a plain one. Weak:
--- it never keeps a closure alive.
--- @type table<function, string>
local action_ids = setmetatable({}, { __mode = "k" })

--- Record that `run` performs the action `id`; returns `run`.
--- @param run function
--- @param id  string|nil  nil leaves it untagged
--- @return function
function Bind.tag_action(run, id)
  if id ~= nil then action_ids[run] = id end
  return run
end

--- The action id a bind's function was tagged with, if any.
--- @param run any
--- @return string|nil
function Bind.action_id(run) return action_ids[run] end

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
--- @return table[]  The handles hl.bind returned, for Bind.is_bound
function Bind.key(keys, action, desc, opts)
  if type(desc) == "table" and opts == nil then
    opts = desc
    desc = nil
  end

  opts = opts or {}

  if desc then
    opts.desc = desc --[[@as string]]
  end

  local made = {}
  for _, key in ipairs(as_list(keys)) do
    local handle = hl.bind(key, action, opts)
    track(key, handle)
    table.insert(made, handle)
  end
  return made
end

--- Like Bind.key but automatically prepends Bind.leader to every key.
--- @param keys   string|string[]
--- @param action HL.Dispatcher|function
--- @param desc   string|HL.BindOptions|nil
--- @param opts   HL.BindOptions|nil
--- @return table[]
function Bind.leader_key(keys, action, desc, opts)
  local prefixed = {}
  for _, k in ipairs(as_list(keys)) do
    table.insert(prefixed, with_prefix(Bind.leader, k))
  end
  return Bind.key(prefixed, action, desc, opts)
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

--- Register a key bound to a plain Lua function (no dispatcher needed).
--- @param keys   string|string[]
--- @param f      function
--- @param desc   string|HL.BindOptions|nil
--- @param opts   HL.BindOptions|nil
function Bind.fn(keys, f, desc, opts, ...)
  local args = { ... }
  Bind.key(keys, function() f(table.unpack(args)) end, desc, opts)
end

--- Like Bind.fn but prepends Bind.leader.
--- @param keys   string|string[]
--- @param f      function
--- @param desc   string|HL.BindOptions|nil
--- @param opts   HL.BindOptions|nil
function Bind.leader_fn(keys, f, desc, opts, ...)
  local args = { ... }
  Bind.leader_key(keys, function() f(table.unpack(args)) end, desc, opts)
end

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

--- Register binds inside a submap; calling it again for an existing submap adds to it.
--- @param name  string                 Submap name
--- @param reset string|function        Submap to return to after a bind fires, or fn when omitted
--- @param fn    function|nil           Registers the binds, e.g. with Bind.key
function Bind.submap(name, reset, fn)
  if fn == nil then
    fn, reset = reset, nil
  end

  local before = {}
  for key, list in pairs(handles[name] or {}) do
    before[key] = #list
  end

  local ok, err
  local function body()
    local previous = scope
    scope = name
    ok, err = xpcall(fn, debug.traceback)
    scope = previous
  end

  if reset then
    hl.define_submap(name, reset, body)
  else
    hl.define_submap(name, body)
  end
  -- Raised only once hl.define_submap has returned, so Hyprland's own current submap is restored whatever it does
  -- with an error from the body, and binds a caller makes after catching this land in the global map.
  if not ok then
    -- The failed submap is unreachable, so drop what the body bound; earlier binds of the same submap stay.
    for key, list in pairs(handles[name] or {}) do
      for index = #list, (before[key] or 0) + 1, -1 do
        remove_handle(list[index])
        list[index] = nil
      end
      if #list == 0 then handles[name][key] = nil end
    end
    error(err, 0)
  end
end

--- Remove binds made through Bind from one submap only; binds made outside Bind aren't tracked.
--- @param keys   string|string[]
--- @param submap string|nil  Submap name; nil or "reset" is the global map
--- @return integer           Number of binds removed
function Bind.unbind(keys, submap)
  local scoped = handles[scope_name(submap)]
  if not scoped then return 0 end

  local count = 0
  for _, key in ipairs(as_list(keys)) do
    local name = normalize(key)
    for _, handle in ipairs(scoped[name] or {}) do
      remove_handle(handle)
      count = count + 1
    end
    scoped[name] = nil
  end

  return count
end

--- Whether a bind made through Bind for `key` is still live in one submap (it was not removed by Bind.unbind).
--- With `handle`, only that bind counts: a later bind on the same key does not make an unbound one live again.
--- @param key    string
--- @param submap string|nil  Submap name; nil or "reset" is the global map
--- @param handle table|nil   A handle from Bind.key
--- @return boolean
function Bind.is_bound(key, submap, handle)
  local scoped = handles[scope_name(submap)]
  local live = scoped and scoped[normalize(key)]
  if not live then return false end
  if handle == nil then return true end
  for _, candidate in ipairs(live) do
    if candidate == handle then return true end
  end
  return false
end

--- The submap that binds are being registered in now; "" is the global map.
--- @return string
function Bind.current_submap() return scope end

--- Like Bind.unbind but prepends Bind.leader to every key.
--- @param keys   string|string[]
--- @param submap string|nil
--- @return integer
function Bind.leader_unbind(keys, submap)
  local prefixed = {}
  for _, k in ipairs(as_list(keys)) do
    table.insert(prefixed, with_prefix(Bind.leader, k))
  end
  return Bind.unbind(prefixed, submap)
end

return Bind
