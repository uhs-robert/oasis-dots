--- Submap lifecycle manager built on top of hl.define_submap / hl.dsp.submap.
--- Tracks current/previous submap state and fires on_enter/on_exit hooks.
--- Use Submap.define() to declare a submap; call .setup() on the result to register binds.
local Bind = require("lib.key.bind")

local Submap = {
  --- @type table<string, SubmapSpec>
  registry = {},
  --- @type string
  current = "reset",
  --- @type string|nil
  previous = nil,
}

--- @class SubmapContext
--- @field current  string        Name of the current (new) submap
--- @field previous string|nil    Name of the submap we came from
--- @field submaps  table         Reference to the Submap module
--- @field [string] any           Extra fields merged in per call-site

--- @class SubmapSpec
--- @field name      string                                          Hyprland submap name
--- @field desc?     string                                          Label shown when entering
--- @field enter?    string|string[]                                 Key(s) that trigger entry (global)
--- @field group?    string                                          Whichkey group for the entry bind
--- @field escape?   "reset"|"previous"|false|fun(ctx: SubmapContext) Exit behaviour; defaults to "reset"
--- @field catchall? "stay"|"reset"|false|fun(ctx: SubmapContext)    Unbound-key behaviour; defaults to false. "stay" swallows unbound keys. "reset" is oneshot — wraps all bound actions to auto-exit and resets on unbound keys.
--- @field on_enter? fun(ctx: SubmapContext)                         Called after entering this submap
--- @field on_exit?  fun(ctx: SubmapContext)                         Called before leaving this submap
--- @field binds?    table[]|fun(): table[]                          Rows passed to Bind.keys inside the submap, or a function returning them

--- @class SubmapHandle
--- @field name  string
--- @field desc  string|nil
--- @field spec  SubmapSpec
--- @field enter fun()   Switch into this submap
--- @field exit  fun()   Exit according to spec.escape
--- @field setup fun()   Register all binds with Hyprland (call once at startup)

--- Build a context table merged with extra fields.
--- @param extra table|nil
--- @return SubmapContext
local function context(extra)
  local ctx = {
    current = Submap.current,
    previous = Submap.previous,
    submaps = Submap,
  }

  for key, value in pairs(extra or {}) do
    ctx[key] = value
  end

  return ctx
end

--- @param spec SubmapSpec
--- @return "reset"|"previous"|false|fun(ctx: SubmapContext)
local function normalize_escape(spec)
  if spec.escape == nil then return "reset" end

  return spec.escape
end

--- @param spec SubmapSpec
--- @return "stay"|"reset"|false|fun(ctx: SubmapContext)
local function normalize_catchall(spec)
  if spec.catchall == nil then return false end

  return spec.catchall
end

--- Activate a named submap, firing exit/enter hooks.
--- @param name string
function Submap.enter(name)
  local next_spec = Submap.registry[name]

  if not next_spec then return end

  local prev_name = Submap.current
  local prev_spec = Submap.registry[prev_name]

  if prev_spec and prev_spec.on_exit then prev_spec.on_exit(context({
    from = prev_name,
    to = name,
  })) end

  Submap.previous = prev_name
  Submap.current = name

  hl.dispatch(hl.dsp.submap(name))

  if next_spec.on_enter then
    next_spec.on_enter(context({
      from = prev_name,
      to = name,
      spec = next_spec,
    }))
  end
end

--- Return to the global (reset) submap, firing the current submap's exit hook.
function Submap.reset()
  local prev_name = Submap.current
  local prev_spec = Submap.registry[prev_name]

  if prev_spec and prev_spec.on_exit then prev_spec.on_exit(context({
    from = prev_name,
    to = "reset",
  })) end

  Submap.previous = prev_name
  Submap.current = "reset"

  hl.dispatch(hl.dsp.submap("reset"))
end

--- Exit the submap according to its spec.escape policy.
--- @param spec SubmapSpec
function Submap.exit(spec)
  local escape = normalize_escape(spec)

  if escape == false then return end

  if escape == "reset" then return Submap.reset() end

  if escape == "previous" then
    if Submap.previous and Submap.previous ~= "reset" then return Submap.enter(Submap.previous) end

    return Submap.reset()
  end

  if type(escape) == "function" then return escape(context({
    spec = spec,
  })) end

  return Submap.reset()
end

--- Handle an unbound keypress according to spec.catchall policy.
--- @param spec SubmapSpec
--- @param key  string
function Submap.handle_catchall(spec, key)
  local catchall = normalize_catchall(spec)

  if catchall == false then return end

  if catchall == "stay" then return end

  if catchall == "reset" then return Submap.reset() end

  if type(catchall) == "function" then return catchall(context({
    key = key,
    spec = spec,
  })) end
end

--- Declare a submap and return a handle with enter/exit/setup methods.
--- Call handle.setup() once during startup to register all binds.
--- @param spec SubmapSpec
--- @return SubmapHandle
function Submap.define(spec)
  Submap.registry[spec.name] = spec

  --- @type SubmapHandle
  local M = {
    name = spec.name,
    desc = spec.desc,
    spec = spec,
  }

  function M.enter() Submap.enter(spec.name) end

  function M.exit() Submap.exit(spec) end

  function M.setup()
    if spec.enter then
      Bind.key(spec.enter, M.enter, spec.desc or ("+" .. spec.name), {
        group = spec.group or "submaps",
      })
    end

    hl.define_submap(spec.name, function()
      local catchall = normalize_catchall(spec)
      local raw_binds = type(spec.binds) == "function" and spec.binds() or spec.binds

      -- "reset" = oneshot: wrap every bound action to exit after firing
      local binds = raw_binds
      if catchall == "reset" then
        binds = {}
        for _, row in ipairs(raw_binds or {}) do
          local action = row[2]
          table.insert(binds, {
            row[1],
            function() if type(action) == "function" then action() else hl.dispatch(action) end M.exit() end,
            row[3],
            row[4],
          })
        end
      end

      Bind.keys(binds or {})

      if normalize_escape(spec) ~= false then
        Bind.key("ESCAPE", M.exit, "Exit " .. spec.name, {
          group = spec.name,
        })
      end

      local catchall_opts = { release = true, ignore_mods = true }
      if catchall == "stay" then
        hl.bind("catchall", hl.dsp.no_op(), catchall_opts)
      elseif catchall == "reset" then
        hl.bind("catchall", function() M.exit() end, catchall_opts)
      elseif type(catchall) == "function" then
        hl.bind("catchall", function() catchall(context({ spec = spec })) end, catchall_opts)
      end
    end)
  end

  return M
end

--- @return table<string, SubmapSpec>
function Submap.get_registry() return Submap.registry end

return Submap
