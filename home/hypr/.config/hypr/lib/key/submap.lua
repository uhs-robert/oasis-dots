--- Submap lifecycle manager built on top of hl.define_submap / hl.dsp.submap.
--- Tracks current/previous submap state and fires on_enter/on_exit hooks.
--- Use Submap.define() to declare a submap; call .setup() on the result to register binds.
local Bind = require("lib.key.bind")

--- @class Submap
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
--- @field escape?   "reset"|"previous"|string|false|fun(ctx: SubmapContext) Exit behaviour; defaults to "reset". A submap name string switches to that submap.
--- @field catchall? "stay"|"reset"|false|fun(ctx: SubmapContext)    Unbound-key behaviour; defaults to false. "stay" swallows unbound keys. "reset" is oneshot — wraps all bound actions to auto-exit and resets on unbound keys.
--- @field on_enter? fun(ctx: SubmapContext)                         Called after entering this submap
--- @field on_exit?  fun(ctx: SubmapContext)                         Called before leaving this submap
--- @field binds?    table[]|fun(): table[]                          Rows passed to Bind.keys inside the submap, or a function returning them

--- @class SubmapHandle
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

--- Fire the on_exit hook for a spec if present.
--- @param spec SubmapSpec|nil
--- @param from string
--- @param to   string
local function fire_exit(spec, from, to)
  if spec and spec.on_exit then spec.on_exit(context({ from = from, to = to })) end
end

--- Resolve the escape policy for a spec, defaulting to "reset".
--- @param spec SubmapSpec
--- @return "reset"|"previous"|string|false|fun(ctx: SubmapContext)
local function normalize_escape(spec)
  if spec.escape == nil then return "reset" end

  return spec.escape
end

--- Resolve the catchall policy for a spec, defaulting to false (disabled).
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

  fire_exit(Submap.registry[prev_name], prev_name, name)

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

  fire_exit(Submap.registry[prev_name], prev_name, "reset")

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

  if type(escape) == "string" then return Submap.enter(escape) end

  if type(escape) == "function" then return escape(context({
    spec = spec,
  })) end

  return Submap.reset()
end

--- Return a function that switches to another submap by name.
--- @param name string
--- @return fun()
function Submap.switch(name)
  return function() Submap.enter(name) end
end

--- Evaluate a binds value, calling it if it is a function.
--- @param binds table[]|fun(): table[]|nil
--- @return table[]|nil
local function resolve_binds(binds)
  if type(binds) == "function" then return binds() end

  return binds
end

--- Invoke an action: calls it directly if it is a function, otherwise dispatches it as a HL dispatcher.
--- @param action HL.Dispatcher|function
local function run(action)
  if type(action) == "function" then return action() end

  return hl.dispatch(action)
end

--- Wrap bind rows so every action calls exit_fn after firing, implementing oneshot behaviour.
--- @param rows    table[]
--- @param exit_fn fun()
--- @return table[]
local function wrap_oneshot(rows, exit_fn)
  local wrapped = {}

  for _, row in ipairs(rows) do
    table.insert(wrapped, {
      row[1],
      function()
        run(row[2])
        exit_fn()
      end,
      row[3],
      row[4],
    })
  end

  return wrapped
end

--- Register the catchall bind for a submap.
--- @param catchall "stay"|"reset"|false|fun(ctx: SubmapContext)
--- @param exit_fn  fun()
--- @param spec     SubmapSpec
local function bind_catchall(catchall, exit_fn, spec)
  local opts = { release = true, ignore_mods = true }
  if catchall == "stay" then
    hl.bind("catchall", hl.dsp.no_op(), opts)
  elseif catchall == "reset" then
    hl.bind("catchall", exit_fn, opts)
  elseif type(catchall) == "function" then
    hl.bind("catchall", function() catchall(context({ spec = spec })) end, opts)
  end
end

--- Declare a submap and return a handle with enter/exit/setup methods.
--- Call handle.setup() once during startup to register all binds.
--- @param spec SubmapSpec
--- @return SubmapHandle
function Submap.define(spec)
  Submap.registry[spec.name] = spec

  local M = {}

  function M.enter() Submap.enter(spec.name) end

  function M.exit() Submap.exit(spec) end

  function M.setup()
    if spec.enter then Bind.key(spec.enter, M.enter, spec.desc or ("+" .. spec.name)) end

    hl.define_submap(spec.name, function()
      local catchall = normalize_catchall(spec)
      local raw_binds = resolve_binds(spec.binds)
      local binds = catchall == "reset" and wrap_oneshot(raw_binds or {}, M.exit) or raw_binds

      Bind.keys(binds or {})

      if normalize_escape(spec) ~= false then Bind.key("ESCAPE", M.exit, "Exit " .. spec.name) end

      bind_catchall(catchall, M.exit, spec)
    end)
  end

  return M
end

return Submap
