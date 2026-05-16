--- Key binding helpers built on top of hl.bind.
--- All binds are recorded in Bind.registry for introspection / whichkey.
--- @class Bind
local Config = require("config")

local Bind = {
  leader = Config.leader,
  --- @type BindEntry[]
  registry = {},
}

--- @class BindOpts
--- @field desc?             string   Short label shown in whichkey
--- @field description?      string   Long description (falls back to desc)
--- @field group?            string   Category used for grouping in whichkey
--- @field submap?           string   Submap name this bind lives in
--- @field submap_universal? boolean  Fires in every submap when true
--- @field hidden?           boolean  Hides from whichkey when true
--- @field leader?           boolean  Prepends Bind.leader to the key
--- @field repeating?        boolean  Bind fires repeatedly while held
--- @field locked?           boolean  Fires even when input is locked (e.g. lockscreen)
--- @field mouse?            boolean  Bind is a mouse button (disables key repeat handling)

--- @class BindEntry
--- @field keys     string
--- @field raw_keys string
--- @field action   any
--- @field desc     string|nil
--- @field group    string|nil
--- @field submap   string|nil
--- @field hidden   boolean
--- @field leader   boolean
--- @field repeating boolean

--- @class DirActions
--- @field left  function
--- @field right function
--- @field up    function
--- @field down  function

--- @class DirDescs
--- @field left?  string
--- @field right? string
--- @field up?    string
--- @field down?  string

--- @param opts BindOpts|string|nil
--- @return BindOpts
local function normalize_opts(opts)
  if type(opts) == "string" then return { desc = opts } end

  return opts or {}
end

--- @param value string|string[]
--- @return string[]
local function as_list(value)
  if type(value) == "table" then return value end

  return { value }
end

--- @param prefix string
--- @param key    string
--- @return string
local function with_prefix(prefix, key)
  if not prefix or prefix == "" then return key end

  return prefix .. " + " .. key
end

--- Coerces a string action into an exec_cmd dispatcher.
--- @param action string|function|any
--- @return any
local function normalize_action(action)
  if type(action) == "string" then return hl.dsp.exec_cmd(action) end

  return action
end

--- Extracts the subset of opts that hl.bind understands.
--- @param opts BindOpts
--- @return table
local function hypr_opts(opts)
  return {
    desc = opts.desc,
    description = opts.description or opts.desc,
    submap = opts.submap,
    submap_universal = opts.submap_universal,
    repeating = opts.repeating,
    locked = opts.locked,
    mouse = opts.mouse,
  }
end

--- Override Bind defaults at runtime. Leader defaults to Config.leader.
--- @param opts { leader?: string }
function Bind.setup(opts)
  opts = opts or {}

  if opts.leader then Bind.leader = opts.leader end
end

--- Register one or more keys to a single action.
--- @param keys   string|string[]  Key string(s); multiples register the same action for each
--- @param action string|function  Shell command string or Lua function
--- @param desc   string|BindOpts|nil
--- @param opts   BindOpts|nil
--- @return BindEntry[]
function Bind.key(keys, action, desc, opts)
  if type(desc) == "table" and opts == nil then
    opts = desc
    desc = nil
  end

  opts = normalize_opts(opts)

  if desc then opts.desc = desc end

  local registered = {}

  for _, key in ipairs(as_list(keys)) do
    local final_key = opts.leader and with_prefix(Bind.leader, key) or key
    local fn = normalize_action(action)

    local entry = {
      keys = final_key,
      raw_keys = key,
      action = action,
      desc = opts.desc or opts.description,
      group = opts.group,
      submap = opts.submap,
      hidden = opts.hidden or false,
      leader = opts.leader or false,
      repeating = opts.repeating or false,
      locked = opts.locked or false,
      mouse = opts.mouse or false,
    }

    table.insert(Bind.registry, entry)
    table.insert(registered, entry)

    hl.bind(final_key, fn, hypr_opts(opts))
  end

  return registered
end

--- Like Bind.key but automatically prepends Bind.leader to every key.
--- @param keys   string|string[]
--- @param action string|function
--- @param desc   string|BindOpts|nil
--- @param opts   BindOpts|nil
--- @return BindEntry[]
function Bind.leader_key(keys, action, desc, opts)
  if type(desc) == "table" and opts == nil then
    opts = desc
    desc = nil
  end

  opts = normalize_opts(opts)
  opts.leader = true

  return Bind.key(keys, action, desc, opts)
end

--- Register a key that runs a shell command.
--- @param keys string|string[]
--- @param cmd  string
--- @param desc string|BindOpts|nil
--- @param opts BindOpts|nil
--- @return BindEntry[]
function Bind.cmd(keys, cmd, desc, opts) return Bind.key(keys, hl.dsp.exec_cmd(cmd), desc, opts) end

--- Like Bind.cmd but prepends Bind.leader.
--- @param keys string|string[]
--- @param cmd  string
--- @param desc string|BindOpts|nil
--- @param opts BindOpts|nil
--- @return BindEntry[]
function Bind.leader_cmd(keys, cmd, desc, opts)
  if type(desc) == "table" and opts == nil then
    opts = desc
    desc = nil
  end

  opts = normalize_opts(opts)
  opts.leader = true

  return Bind.cmd(keys, cmd, desc, opts)
end

--- Register a single bind from a spec table.
--- @param spec     { keys: string|string[], run?: any, action?: any, cmd?: any, desc?: string, description?: string, group?: string, submap?: string, submap_universal?: boolean, hidden?: boolean, leader?: boolean }
--- @param defaults BindOpts|nil
--- @return BindEntry[]
function Bind.map(spec, defaults)
  defaults = defaults or {}

  return Bind.key(spec.keys, spec.run or spec.action or spec.cmd, spec.desc or spec.description, {
    group = spec.group or defaults.group,
    submap = spec.submap or defaults.submap,
    submap_universal = spec.submap_universal or defaults.submap_universal,
    hidden = spec.hidden or defaults.hidden,
    leader = spec.leader ~= nil and spec.leader or defaults.leader,
  })
end

--- Register multiple binds from a row table.
--- Each row is { keys, action, desc, opts? } where opts is a BindOpts table.
--- @param group    string
--- @param rows     { [1]: string|string[], [2]: any, [3]: string, [4]: BindOpts|nil }[]
--- @param defaults BindOpts|nil
--- @return BindEntry[]
function Bind.keys(group, rows, defaults)
  defaults = defaults or {}

  local registered = {}

  for _, row in ipairs(rows or {}) do
    local row_opts = row[4] or {}

    local entries = Bind.key(row[1], row[2], row[3], {
      group = row_opts.group or defaults.group or group,
      submap = row_opts.submap or defaults.submap,
      submap_universal = row_opts.submap_universal or defaults.submap_universal,
      hidden = row_opts.hidden or defaults.hidden,
      leader = row_opts.leader ~= nil and row_opts.leader or defaults.leader,
      repeating = row_opts.repeating ~= nil and row_opts.repeating or defaults.repeating,
      locked = row_opts.locked ~= nil and row_opts.locked or defaults.locked,
      mouse = row_opts.mouse ~= nil and row_opts.mouse or defaults.mouse,
    })

    for _, entry in ipairs(entries) do
      table.insert(registered, entry)
    end
  end

  return registered
end

--- Register H/J/K/L + arrow keys for a set of directional actions.
--- @param actions DirActions
--- @param descs   DirDescs|nil
--- @param opts    BindOpts|nil
--- @return BindEntry[]
function Bind.dir(actions, descs, opts)
  descs = descs or {}
  opts = normalize_opts(opts)

  return Bind.keys(opts.group or "directional", {
    { { "H", "LEFT" }, actions.left, descs.left or "Left" },
    { { "J", "DOWN" }, actions.down, descs.down or "Down" },
    { { "K", "UP" }, actions.up, descs.up or "Up" },
    { { "L", "RIGHT" }, actions.right, descs.right or "Right" },
  }, opts)
end

--- @return BindEntry[]
function Bind.get_registry() return Bind.registry end

return Bind
