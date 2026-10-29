--- Submap lifecycle manager built on top of Bind.submap (hl.define_submap) / hl.dsp.submap.
--- Tracks current/previous submap state and fires on_enter/on_exit hooks.
--- Use Submap.define() to declare a submap; call .setup() on the result to register binds.
local Act = require("lib.act") ---@class ActionLib
local Bind = require("lib.key.bind") ---@class BindLib
local SubmapHint = require("lib.key.submap_hint") ---@class SubmapHint

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
--- @field binds?    table[]|fun(): table[]                          Rows passed to Bind.keys inside the submap, or a function returning them. A row is { keys, action, desc?, opts? }; `action` may be an action id ("window.close") or { id, args } ("popup.open", { "clock" }), which takes the action's label unless `desc` is given (false for none).
--- @field hint?     SubmapHintGroup[]                               Groups for the compact hint bar shown on entry in place of HyprVim's which-key popup (SHIFT + / still opens that); see lib/key/submap_hint.lua
--- @field targets?  boolean                                         Its keys act on the focused window or the selection (lib/selection.lua): selected windows get a thick border and Quickshell numbers them while it is up, and the selection carries between submaps that set this and clears on any other switch

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

--- @param name string
--- @return boolean
local function has_targets(name)
  local spec = Submap.registry[name]
  return spec ~= nil and spec.targets == true
end

--- Clear the window selection on a switch that leaves the `targets` submaps or comes into them from outside: a
--- selection made outside (hypr-act, voice) must not reach the first key, nor one made here a later visit.
--- @param from string
--- @param to   string
local function settle_selection(from, to)
  if has_targets(from) and has_targets(to) then return end
  local Selection = require("lib.selection")
  if has_targets(to) then
    Selection.resync()
  else
    Selection.clear()
  end
end

local watching_submap_event = false

--- Clear the selection on the routes into a plain submap that skip Submap.enter and Submap.reset (a raw
--- `hl.dsp.submap` from a script or plugin), and keep its borders in step with the config. Hooked once per config load,
--- by the first submap with `targets`.
local function watch_submap_event()
  if watching_submap_event then return end
  watching_submap_event = true
  hl.on("keybinds.submap", function(name)
    if not has_targets(name) then require("lib.selection").clear() end
  end)
  require("lib.selection").follow_config()
end

--- Activate a named submap, firing exit/enter hooks.
--- @param name string
function Submap.enter(name)
  local next_spec = Submap.registry[name]

  if not next_spec then return end

  local prev_name = Submap.current

  fire_exit(Submap.registry[prev_name], prev_name, name)
  settle_selection(prev_name, name)

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

  if next_spec.hint then SubmapHint.send(name) end
end

--- Return to the global (reset) submap, firing the current submap's exit hook.
function Submap.reset()
  local prev_name = Submap.current

  fire_exit(Submap.registry[prev_name], prev_name, "reset")
  settle_selection(prev_name, "reset")

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

--- Go back to the previous submap, or reset if there is none.
function Submap.back()
  local prev = Submap.previous
  if prev and prev ~= "reset" then
    Submap.enter(prev)
    Submap.previous = nil
    return
  end
  Submap.reset()
  -- Delay past the listener's reset teardown, which would close the HUD.
  hl.timer(function() require("lua.plugins.hyprvim").whichkey.toggle() end, { timeout = 150, type = "oneshot" })
end

--- Toggle the which-key HUD without changing submap. Public so the bind dump (home/hypr/tests/registry_binds.lua) can
--- tell this bind from another unlabelled key.
function Submap.toggle_whichkey() require("lua.plugins.hyprvim").whichkey.toggle() end

--- Evaluate a binds value, calling it if it is a function.
--- @param binds table[]|fun(): table[]|nil
--- @return table[]|nil
local function resolve_binds(binds)
  if type(binds) == "function" then return binds() end

  return binds
end

--- Whether a row's action names an `Act` action (an id, or { id, args }) rather than a function or dispatcher.
--- @param action any
--- @return boolean
local function names_action(action)
  return type(action) == "string" or (type(action) == "table" and type(action[1]) == "string")
end

--- Replace each row that names an action with a plain row; a row whose action does not resolve is dropped. The second
--- result is the rows that survived as written, action ids intact, for the hint bar to read.
--- @param rows table[]
--- @return table[] resolved, table[] kept
local function resolve_action_rows(rows)
  local resolved, kept = {}, {}
  for _, row in ipairs(rows) do
    if not names_action(row[2]) then
      table.insert(resolved, row)
      table.insert(kept, row)
    else
      local run, label = Act.row_action(row[2])
      if run then
        local desc = row[3]
        if desc == nil then desc = label end
        table.insert(resolved, { row[1], run, desc or nil, row[4] })
        table.insert(kept, row)
      end
    end
  end
  return resolved, kept
end

--- Invoke an action: calls it directly if it is a function, otherwise dispatches it as a HL dispatcher.
--- @param action HL.Dispatcher|function
local function run(action)
  if type(action) == "function" then return action() end

  return hl.dispatch(action)
end

--- Wrap individual bind rows that have opts.oneshot = true, marking them keep=true to prevent double-wrap.
--- @param rows    table[]
--- @param exit_fn fun()
--- @return table[]
local function apply_individual_oneshots(rows, exit_fn)
  local result = {}
  for _, row in ipairs(rows) do
    local opts = row[4]
    if type(opts) == "table" and opts.oneshot then
      table.insert(result, {
        row[1],
        Bind.tag_action(function()
          run(row[2])
          exit_fn()
        end, Bind.action_id(row[2])),
        row[3],
        { keep = true },
      })
    else
      table.insert(result, row)
    end
  end
  return result
end

--- Wrap bind rows so every action calls exit_fn after firing, implementing oneshot behaviour.
--- @param rows    table[]
--- @param exit_fn fun()
--- @return table[]
local function wrap_oneshot(rows, exit_fn)
  local wrapped = {}

  for _, row in ipairs(rows) do
    local opts = row[4]
    if type(opts) == "table" and opts.keep then
      table.insert(wrapped, row)
    else
      table.insert(wrapped, {
        row[1],
        Bind.tag_action(function()
          run(row[2])
          exit_fn()
        end, Bind.action_id(row[2])),
        row[3],
        opts,
      })
    end
  end

  return wrapped
end

--- The keys Hyprland treats as modifiers when pressed alone, less Caps_Lock and Num_Lock, which toggle a lock.
local lone_modifier_keys = { "Shift_L", "Shift_R", "Control_L", "Control_R", "Alt_L", "Alt_R", "Super_L", "Super_R" }

--- Mouse buttons (left, right, middle, side, extra) and wheel directions, in Hyprland's bind names.
local mouse_inputs = {
  "mouse:272",
  "mouse:273",
  "mouse:274",
  "mouse:275",
  "mouse:276",
  "mouse_up",
  "mouse_down",
  "mouse_left",
  "mouse_right",
}

--- Register the catchall bind for a submap.
--- @param catchall "stay"|"reset"|false|fun(ctx: SubmapContext)
--- @param exit_fn  fun()
--- @param spec     SubmapSpec
local function bind_catchall(catchall, exit_fn, spec)
  -- Hyprland 0.57 runs a catchall on the key press, whatever its `release` flag, and a modifier pressed alone
  -- claims no bind, so holding Ctrl for a `CTRL + X` row would exit a one-shot submap before X arrives. These
  -- no-ops claim the modifier presses; transparent, so a modifier held during another bind is not shadowed.
  if catchall == "reset" or type(catchall) == "function" then
    Bind.key(lone_modifier_keys, hl.dsp.no_op(), { ignore_mods = true, transparent = true })
  end

  local action
  if catchall == "stay" then
    action = hl.dsp.no_op()
  elseif catchall == "reset" then
    action = exit_fn
  elseif type(catchall) == "function" then
    action = function() catchall(context({ spec = spec })) end
  else
    return
  end

  -- Hyprland 0.57 also runs a catchall on mouse button and wheel events, so it swallowed every click and scroll (the
  -- Cursor submap's own wlrctl clicks included). These binds do what the catchall does, and a bind that matches keeps
  -- the catchall from running; non_consuming hands the event on to the window.
  Bind.key(mouse_inputs, action, { ignore_mods = true, non_consuming = true, transparent = true })
  Bind.key("catchall", action, { release = true, ignore_mods = true })
end

local whichkey_toggle_key = "SHIFT + SLASH"

--- Whether any bind row already uses the key, compared the way Hyprland does (case and whitespace ignored).
--- @param rows table[]
--- @param key  string
--- @return boolean
local function binds_use_key(rows, key)
  local wanted = key:gsub("%s+", ""):lower()

  for _, row in ipairs(rows) do
    local keys = type(row[1]) == "table" and row[1] or { row[1] }

    for _, candidate in ipairs(keys) do
      if candidate:gsub("%s+", ""):lower() == wanted then return true end
    end
  end

  return false
end

--- Bind the which-key toggle in the submap being registered.
--- @param catchall "stay"|"reset"|false|fun(ctx: SubmapContext)
local function bind_whichkey_toggle(catchall)
  -- No description, so which-key does not list the toggle as a row in every submap.
  Bind.key(whichkey_toggle_key, Submap.toggle_whichkey)

  -- For Hyprland 0.56, whose catchall runs on key release: claims the `/` key-up when it outlasts Shift (ignore_mods
  -- matches the bare `/`). bind_catchall's modifier no-ops claim the Shift key-up.
  if catchall == "reset" or type(catchall) == "function" then
    Bind.key("SLASH", hl.dsp.no_op(), { ignore_mods = true, transparent = true })
  end
end

--- Declare a submap and return a handle with enter/exit/setup methods.
--- Call handle.setup() once during startup to register all binds; the submap is enterable only after it succeeds.
--- @param spec SubmapSpec
--- @return SubmapHandle
function Submap.define(spec)
  local M = {}

  function M.enter() Submap.enter(spec.name) end

  function M.exit() Submap.exit(spec) end

  function M.back() Submap.back() end

  function M.setup()
    Bind.submap(spec.name, function()
      local catchall = normalize_catchall(spec)
      local resolved, bound_rows = resolve_action_rows(resolve_binds(spec.binds) or {})
      local raw_binds = apply_individual_oneshots(resolved, M.exit)
      local binds = catchall == "reset" and wrap_oneshot(raw_binds, M.exit) or raw_binds

      Bind.keys(binds or {})

      if spec.hint then
        SubmapHint.register(spec.name, spec.hint, bound_rows, {
          escape = normalize_escape(spec) ~= false,
          whichkey = not binds_use_key(raw_binds, whichkey_toggle_key),
          targets = spec.targets == true,
        })
      end

      if normalize_escape(spec) ~= false then
        Bind.key("ESCAPE", M.exit, "Exit " .. spec.name)
        -- Before 0.57 a one-shot Back runs on key-up: on key-down, the key-up would reach the catchall of the submap
        -- it went back to. 0.57 matches the key-up in the submap the key went down in, while a key-up bind there lets
        -- its key-down through to the focused app.
        local back_opts = catchall == "reset" and not Bind.keybinds_v2 and { release = true } or nil
        Bind.key("BackSpace", M.back, "Back", back_opts)
      end

      if not binds_use_key(raw_binds, whichkey_toggle_key) then bind_whichkey_toggle(catchall) end

      bind_catchall(catchall, M.exit, spec)
    end)

    -- Registered only once the body succeeded: a submap whose setup raised has no Escape bind and must stay unknown
    -- to Submap.enter and the submap.enter action.
    Submap.registry[spec.name] = spec
    if spec.targets then watch_submap_event() end

    -- After the body, which raises when it fails: an entry key into a half-built submap with no Escape would strand
    -- the user there.
    if spec.enter then Bind.key(spec.enter, M.enter, spec.desc or ("+" .. spec.name)) end
  end

  return M
end

return Submap
