--- Key binding helpers built on top of hl.bind.

local Config = require("config")
local Json = require("lib.json") ---@class Json
local Scripts = require("lib.scripts") ---@class Scripts

--- @class BindLib
local Bind = {
  leader = Config.leader,
  --- Folder holding actions.json; nil means oasis-djinn's own lookup ($OASIS_DJINN_CONFIG_DIR, else ~/.config/oasis-djinn).
  manifest_dir = nil,
  --- Path of the oasis-djinn binary whose presence is tested; nil means ~/.local/bin/oasis-djinn.
  djinn_bin = nil,
}

-- hl.unbind drops a key from every submap (hyprwm/Hyprland#15040), so handles are kept per submap
-- for Bind.unbind. Bind.unbind and Bind.submap are public API for custom/; keep their signatures stable.

--- Submap that binds are currently being registered in; "" is the global map. Set by Bind.submap.
local scope = ""

--- @type table<string, table<string, table[]>> submap -> normalized key -> bind handles
local handles = {}

--- Action id of the Bind.action call registering binds right now; nil for every other bind.
local registering_action = nil

--- Bind handle -> the action id it performs, for the bind dump (home/hypr/tests/bind_dump.lua). Weak keys, so a
--- removed bind does not stay alive through this table.
--- @type table<table, string>
Bind.action_ids = setmetatable({}, { __mode = "k" })

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
  if registering_action then Bind.action_ids[handle] = registering_action end
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

--- The per-tool binding files, read by name: Hyprland's Lua cannot list a directory. The registry check fails a
--- bindings/*.json missing here.
local BINDING_FILES = { "bindings/quickshell.json", "bindings/hyprland.json" }

--- @type table<string, table>|nil action id -> its performer from BINDING_FILES, read on first use
local bindings

--- @type table|nil lib.actions.performers once required; a failed load is not cached, so every lua bind warns
local performers

--- @type boolean|nil whether the oasis-djinn binary was executable at the first Bind.action
local djinn_present

--- @type string[] every Bind.action problem so far, in order; tests read it
Bind.warnings = {}

local warning_scheduled = false

--- Record a config-time problem and show one notification for all of them. Lua config errors would abort the
--- rest of the file, so a bad action id is reported here instead and only its own bind is skipped.
--- @param message string
local function warn(message)
  table.insert(Bind.warnings, message)
  if warning_scheduled then return end
  warning_scheduled = true
  -- Deferred like lib/missing_repos.lua: the notification waits until the config has finished loading, and the
  -- one-shot lets every bind in the file add its warning first.
  hl.timer(function()
    warning_scheduled = false
    hl.notification.create({ text = table.concat(Bind.warnings, "\n"), timeout = 20000 })
  end, { timeout = 2000, type = "oneshot" })
end

--- Forget the cached manifest so the next Bind.action rereads it.
function Bind.reload_manifest()
  manifest, bindings, djinn_present, performers = nil, nil, nil, nil
end

--- @param name string  Path under the manifest folder, e.g. "actions.json"
--- @return table
local function read_manifest_file(name)
  local dir = Bind.manifest_dir
    or os.getenv("OASIS_DJINN_CONFIG_DIR")
    or ((os.getenv("HOME") or "") .. "/.config/oasis-djinn")
  local path = dir .. "/" .. name
  local file, open_err = io.open(path, "r")
  if not file then
    error("Bind.action: cannot read " .. path .. " (" .. tostring(open_err) .. "); is oasis-djinn stowed?", 0)
  end
  local text = file:read("a")
  file:close()

  local decoded, parsed = pcall(Json.decode, text)
  if not decoded or type(parsed) ~= "table" then error("Bind.action: " .. path .. " is not valid JSON", 0) end
  return parsed
end

--- An unreadable manifest warns once and yields an empty one, so every Bind.action skips quietly after that
--- rather than repeating the same warning per bind.
--- @return table<string, table>
local function load_manifest()
  if manifest then return manifest end

  local read_ok, parsed = pcall(read_manifest_file, "actions.json")
  if read_ok and type(parsed.actions) ~= "table" then
    read_ok, parsed = false, "Bind.action: actions.json holds no actions"
  end
  manifest = {}
  if not read_ok then
    warn(tostring(parsed) .. "; no manifest binds were registered")
    return manifest
  end
  for _, entry in ipairs(parsed.actions) do
    manifest[entry.id] = entry
  end
  return manifest
end

--- Single-quote a word for the shell unless it is plain. Only a leading `~/` stays outside the quotes so the shell
--- expands it, as oasis-djinn does; any other `~` (`~`, `~user`) is quoted because the runner leaves it literal.
--- @param word string
--- @return string
local function shell_word(word)
  local home, rest = word:match("^(~/)(.*)$")
  local body = rest or word
  if body:match("^[%w_%-%./=:,+@]+$") then return word end
  return (home or "") .. "'" .. body:gsub("'", "'\\''") .. "'"
end

--- The binding of an action id from any tool's file; nil, after a warning, when none has it. An unreadable file
--- warns once and counts as empty.
--- @param id string
--- @return table|nil
local function binding_of(id)
  if not bindings then
    bindings = {}
    for _, name in ipairs(BINDING_FILES) do
      local read_ok, parsed = pcall(read_manifest_file, name)
      if not read_ok then
        warn(tostring(parsed))
        parsed = {}
      end
      for bound_id, binding in pairs(parsed.bindings or {}) do
        bindings[bound_id] = bindings[bound_id] or binding
      end
    end
  end
  local binding = bindings[id]
  if not binding then
    warn("Bind.action: no binding for action '" .. id .. "' in " .. table.concat(BINDING_FILES, ", "))
  end
  return binding
end

--- The function performing a `lua` action; nil, after a warning, when performers.lua lacks it or fails to load. The
--- require is guarded because a load error there would otherwise abort the whole keymap file.
--- @param id string
--- @return function|nil
local function performer_of(id)
  if performers == nil then
    local loaded, module = pcall(require, "lib.actions.performers")
    if not loaded then
      warn(
        "Bind.action: lib/actions/performers.lua failed to load (" .. tostring(module) .. "); its binds were skipped"
      )
      return nil
    end
    performers = module
  end
  local perform = performers.get(id)
  if not perform then warn("Bind.action: lib/actions/performers.lua has no function for action '" .. id .. "'") end
  return perform
end

--- Each param's value by name: from args in order, else the manifest default. Nil, after a warning, when a required
--- param has no value.
--- @param entry table  Manifest entry
--- @param args  table
--- @return table<string, any>|nil
local function param_values(entry, args)
  local values = {}
  for index, param in ipairs(entry.params or {}) do
    local value = args[index]
    if value == nil then value = param.default end
    if value == nil then
      warn("Bind.action: action '" .. entry.id .. "' needs param " .. param.name .. " in opts.args")
      return nil
    end
    values[param.name] = value
  end
  return values
end

--- The command that performs an action without the runner: what oasis-djinn would run for an ipc or command binding,
--- each `{param}` filled once from `values` (a value holding `{other}` stays literal, as in oasis-djinn).
--- @param binding table
--- @param values  table<string, any>
--- @return string
local function direct_command(binding, values)
  local words
  if binding.kind == "ipc" then
    words = { Scripts.qs_ipc, "call", binding.target, binding["function"] }
    for _, arg in ipairs(binding.args or {}) do
      table.insert(words, arg)
    end
  else
    words = binding.argv
  end
  local quoted = {}
  for _, word in ipairs(words) do
    local filled = word:gsub("{([%w_]+)}", function(name)
      if values[name] ~= nil then return tostring(values[name]) end
    end)
    table.insert(quoted, shell_word(filled))
  end
  return table.concat(quoted, " ")
end

--- True when the runner is installed; it is not on `install.sh -m`/`--no-cargo` or after a failed build.
--- Tested once, at config load. Readable file, not an exec-bit test: Hyprland's Lua has no usable `os.execute`.
--- @return boolean
local function runner_installed()
  if djinn_present == nil then
    local path = Bind.djinn_bin or ((os.getenv("HOME") or "") .. "/.local/bin/oasis-djinn")
    local file = io.open(path, "r")
    djinn_present = file ~= nil
    if file then file:close() end
  end
  return djinn_present
end

--- The dispatcher or function a bind of `entry` runs; nil after a warning. A `lua` action calls its performer
--- in-process, so a repeating key never waits on a process; any other runs `oasis-djinn <id> <args>`, or without the
--- runner the command it would run.
--- @param entry table
--- @param args  table
--- @return HL.Dispatcher|function|nil
local function bind_target(entry, args)
  local id = entry.id
  local binding = binding_of(id)
  if not binding then return nil end
  local values = param_values(entry, args)
  if not values then return nil end
  if binding.kind == "lua" then
    local perform = performer_of(id)
    if not perform then return nil end
    -- Positional, with manifest defaults filled in, so a performer sees the same params as `oasis-djinn <id>`.
    local filled = {}
    for index, param in ipairs(entry.params or {}) do
      filled[index] = values[param.name]
    end
    local count = #(entry.params or {})
    return function() perform(table.unpack(filled, 1, count)) end
  end
  if runner_installed() then
    local words = { Scripts.djinn, id }
    for _, arg in ipairs(args) do
      table.insert(words, shell_word(tostring(arg)))
    end
    return hl.dsp.exec_cmd(table.concat(words, " "))
  end
  return hl.dsp.exec_cmd(direct_command(binding, values))
end

--- Register an action from the oasis-djinn manifest: its key, extra keys and label come from there, and the
--- bind performs it (bind_target). An unknown id, a missing binding or performer, or an action the runner-less
--- fallback cannot perform, warns and skips only that bind.
--- @param id   string
--- @param opts table|nil  `key` replaces the manifest's main key (a key string, or `{key, leader?, universal?}`); the
---                        extra keys and label stay. `args` is the action's params in order: passed to a `lua`
---                        performer, appended to `oasis-djinn <id>`. Everything else (e.g. `submap_universal`) goes
---                        to hl.bind and beats the manifest's `universal` flag.
function Bind.action(id, opts)
  local entry = load_manifest()[id]
  if not entry then
    -- An empty manifest was already reported by load_manifest.
    if next(manifest) ~= nil then warn("Bind.action: unknown action id '" .. tostring(id) .. "'") end
    return
  end

  opts = opts or {}
  local main_key = entry.key
  if type(opts.key) == "string" then
    main_key = { key = opts.key, leader = false, universal = entry.key and entry.key.universal }
  elseif opts.key ~= nil then
    main_key = opts.key
  end

  -- A keyless action (one only oasis-djinn reaches) binds just its extras, or nothing without opts.key.
  local keys = { main_key }
  for _, extra in ipairs(entry.extra_keys or {}) do
    table.insert(keys, extra)
  end
  if #keys == 0 then
    warn("Bind.action: action '" .. id .. "' has no key; pass opts.key")
    return
  end

  local run = bind_target(entry, opts.args or {})
  if not run then return end
  registering_action = id
  for _, spec in ipairs(keys) do
    local bind_opts = {}
    for k, v in pairs(opts) do
      if k ~= "key" and k ~= "args" then bind_opts[k] = v end
    end
    if bind_opts.submap_universal == nil and spec.universal then bind_opts.submap_universal = true end
    local register = spec.leader and Bind.leader_key or Bind.key
    register(spec.key, run, entry.label, bind_opts)
  end
  registering_action = nil
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
