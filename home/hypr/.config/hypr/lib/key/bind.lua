--- Key binding helpers built on top of hl.bind.

local Config = require("config")
local Json = require("lib.json") ---@class Json
local Scripts = require("lib.scripts") ---@class Scripts

--- @class BindLib
local Bind = {
  leader = Config.leader,
  --- Folder holding actions.json; nil means oasis-djinn's own lookup ($OASIS_DJINN_CONFIG_DIR, else ~/.config/oasis-djinn).
  manifest_dir = nil,
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

--- @type table<string, table>|nil action id -> manifest entry, read on first use
local manifest

--- Forget the cached manifest so the next Bind.action rereads it.
function Bind.reload_manifest() manifest = nil end

--- @return table<string, table>
local function load_manifest()
  if manifest then return manifest end

  local dir = Bind.manifest_dir
    or os.getenv("OASIS_DJINN_CONFIG_DIR")
    or ((os.getenv("HOME") or "") .. "/.config/oasis-djinn")
  local path = dir .. "/actions.json"
  local file, open_err = io.open(path, "r")
  -- Raise rather than skip: a quietly missing bind is worse than a config that says why it did not load.
  if not file then
    error("Bind.action: cannot read " .. path .. " (" .. tostring(open_err) .. "); is oasis-djinn stowed?", 0)
  end
  local text = file:read("a")
  file:close()

  local decoded, parsed = pcall(Json.decode, text)
  if not decoded or type(parsed) ~= "table" or type(parsed.actions) ~= "table" then
    error("Bind.action: " .. path .. " is not a valid actions manifest", 0)
  end

  manifest = {}
  for _, entry in ipairs(parsed.actions) do
    manifest[entry.id] = entry
  end
  return manifest
end

--- Register an action from the oasis-djinn manifest: its key, extra keys and label come from there, and the
--- bind runs `oasis-djinn <id>`. Raises on an unknown id.
--- @param id   string
--- @param opts table|nil  `key` replaces the manifest's main key (a key string, or `{key, leader?, universal?}`); the
---                        extra keys and label stay. Everything else (e.g. `submap_universal`) goes to hl.bind and
---                        beats the manifest's `universal` flag.
function Bind.action(id, opts)
  local entry = load_manifest()[id]
  if not entry then error("Bind.action: unknown action id '" .. tostring(id) .. "'", 0) end

  opts = opts or {}
  local main_key = entry.key
  if type(opts.key) == "string" then
    main_key = { key = opts.key, leader = false, universal = entry.key.universal }
  elseif opts.key ~= nil then
    main_key = opts.key
  end

  local keys = { main_key }
  for _, extra in ipairs(entry.extra_keys or {}) do
    table.insert(keys, extra)
  end

  local run = hl.dsp.exec_cmd(Scripts.djinn .. " " .. id)
  for _, spec in ipairs(keys) do
    local bind_opts = {}
    for k, v in pairs(opts) do
      if k ~= "key" then bind_opts[k] = v end
    end
    if bind_opts.submap_universal == nil and spec.universal then bind_opts.submap_universal = true end
    local register = spec.leader and Bind.leader_key or Bind.key
    register(spec.key, run, entry.label, bind_opts)
  end
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

  local function body()
    local previous = scope
    scope = name
    local ok, err = xpcall(fn, debug.traceback)
    scope = previous
    if not ok then error(err, 0) end
  end

  if reset then
    hl.define_submap(name, reset, body)
  else
    hl.define_submap(name, body)
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
