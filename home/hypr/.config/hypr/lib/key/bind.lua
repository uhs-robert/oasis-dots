--- Key binding helpers built on top of hl.bind.

local Config = require("config")

--- @class BindLib
local Bind = {
  leader = Config.leader,
}

-- Bind.unbind is the supported way to remove a bind, scoped to one submap. Hyprland's own hl.unbind(key)
-- removes the key from the global map and every submap, and through 0.56 so does a bind handle's
-- :remove() (hyprwm/Hyprland#15040). So every bind made here keeps its handle under its submap, and
-- Bind.unbind acts on those alone. Keep its signature stable: if Hyprland gains a scoped unbind, use it
-- inside Bind.unbind rather than changing what callers write.

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

--- True when a bind handle's :remove() drops only that bind, which the keybind rewrite after 0.56 made so
--- (hyprwm/Hyprland#15568). Older releases, and -git builds still reporting 0.56, disable the bind instead.
local SCOPED_REMOVE = (function()
  local version = type(hl.version) == "function" and hl.version() or nil
  if type(version) ~= "string" then return false end
  local major, minor = version:match("^(%d+)%.(%d+)")
  major, minor = tonumber(major), tonumber(minor)
  if not major then return false end
  return major > 0 or minor >= 57
end)()

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
    track(key, hl.bind(key, action, opts))
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

--- Register binds inside a submap, so Bind.unbind can tell them apart from the same key elsewhere.
--- Use it instead of hl.define_submap; calling it again for an existing submap adds to it.
--- @param name  string                 Submap name
--- @param reset string|function        Submap to return to after a bind fires, or fn when omitted
--- @param fn    function|nil           Registers the binds, e.g. with Bind.key
function Bind.submap(name, reset, fn)
  if fn == nil then
    fn, reset = reset, nil
  end

  local function body()
    local previous = scope
    scope = name
    local ok, err = pcall(fn)
    scope = previous
    if not ok then error(err, 0) end
  end

  if reset then
    hl.define_submap(name, reset, body)
  else
    hl.define_submap(name, body)
  end
end

--- Remove binds made through Bind from one submap only, leaving the same key in every other submap.
--- Keys match the way they were bound, ignoring case and spaces; "SUPER + H" removes Bind.leader_key("H").
--- Binds made outside Bind (raw hl.bind, HyprVim) aren't tracked; hl.unbind is the only way to drop those.
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
      if SCOPED_REMOVE then
        handle:remove()
      else
        handle:set_enabled(false)
      end
      count = count + 1
    end
    scoped[name] = nil
  end

  return count
end

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
