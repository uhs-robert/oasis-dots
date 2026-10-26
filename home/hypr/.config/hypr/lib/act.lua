--- Actions: one id, label, typed params and key per thing the desktop can do.
---
--- `Act.define` registers an action and binds its default key; `Act.bind` adds another key (a loop key with
--- args, a submap row, a custom/ override). `Act.run` and `Act.run_cli` perform one by id, so keys, the
--- `hypr-act` script, the bar and voice share one path. Config-time mistakes warn and skip only the bad entry,
--- because a Lua error would abort the rest of the config file.

local Bind = require("lib.key.bind") ---@class BindLib
local Json = require("lib.json") ---@class Json
local Scripts = require("lib.scripts") ---@class Scripts

--- @class ActionParam
--- @field name    string
--- @field type    "int"|"float"|"string"|"bool"|"enum"
--- @field values  string[]|nil  Enum members
--- @field default any|nil       Makes the param optional; only a trailing run of params may have one

--- @class ActionKey
--- @field key       string
--- @field leader    boolean
--- @field universal boolean

--- @class ActionHandle
--- @field id         string
--- @field label      string
--- @field intent     string|nil
--- @field params     ActionParam[]
--- @field key        ActionKey|nil
--- @field extra_keys ActionKey[]
--- @field opts       table
--- @field bound_keys table[]   Every key registered so far, default or added with Act.bind; list drops the unbound ones
--- @field run        function|table  Lua function, or an Ipc/Cmd table

--- @class ActionLib
local Act = {
  --- Every config-time problem so far, in order; tests read it.
  warnings = {},
}

--- @type table<string, ActionHandle>
local registry = {}

local ID_PATTERN = "^[a-z][a-z0-9]*%.[a-z][a-z0-9_]*$"
local NAME_PATTERN = "^[a-z][a-z0-9_]*$"
local PARAM_TYPES = { int = true, float = true, string = true, bool = true, enum = true }
local MAX_SAFE_INT = 2 ^ 53

local warning_scheduled = false

--- Record a config-time problem and show one notification for all of them.
--- @param message string
local function warn(message)
  table.insert(Act.warnings, message)
  if warning_scheduled then return end
  warning_scheduled = true
  -- Deferred like lib/missing_repos.lua: the notification waits until the config has finished loading, and the
  -- one-shot lets every define in the config add its warning first.
  hl.timer(function()
    warning_scheduled = false
    local text = table.concat(Act.warnings, "\n")
    -- Cleared once shown, so a later notification lists only what is new.
    Act.warnings = {}
    hl.notification.create({ text = text, timeout = 20000 })
  end, { timeout = 2000, type = "oneshot" })
end

---------------------------------------------------------------------------------------------------
-- Typed values
---------------------------------------------------------------------------------------------------

--- Why `value`, already a Lua value, is not valid for `param`; nil when it is.
--- @param param ActionParam
--- @param value any
--- @return string|nil
local function value_problem(param, value)
  local kind = param.type
  if kind == "int" then
    local is_int = type(value) == "number" and value % 1 == 0 and math.abs(value) < MAX_SAFE_INT
    if not is_int then return "expects an int, got " .. tostring(value) end
  elseif kind == "float" then
    local finite = type(value) == "number" and value == value and math.abs(value) ~= math.huge
    if not finite then return "expects a float, got " .. tostring(value) end
  elseif kind == "string" then
    if type(value) ~= "string" then return "expects a string, got " .. tostring(value) end
    -- exec_cmd truncates a command line at a NUL byte.
    if value:find("\0", 1, true) then return "must not contain a NUL byte" end
  elseif kind == "bool" then
    if type(value) ~= "boolean" then return "expects a bool, got " .. tostring(value) end
  elseif kind == "enum" then
    for _, member in ipairs(param.values) do
      if member == value then return nil end
    end
    return "expects one of " .. table.concat(param.values, "|") .. ", got " .. tostring(value)
  end
  return nil
end

--- Parse one command-line word as `param`'s type. Strict on purpose: no hex, no inf/nan, no "1.0" for an int.
--- @param param ActionParam
--- @param word  string
--- @return any|nil value, string|nil problem
local function parse_word(param, word)
  local kind = param.type
  if kind == "int" then
    -- Compared after parsing, so run and run_cli accept exactly the same range.
    local value = word:match("^[+-]?%d+$") and tonumber(word)
    if not value or math.abs(value) >= MAX_SAFE_INT then return nil, "expects an int, got '" .. word .. "'" end
    return value
  elseif kind == "float" then
    local mantissa = word:gsub("[eE][+-]?%d+$", "")
    local shaped = mantissa:match("^[+-]?%d+%.?%d*$") or mantissa:match("^[+-]?%.%d+$")
    local value = shaped and tonumber(word)
    if not value or math.abs(value) == math.huge then return nil, "expects a float, got '" .. word .. "'" end
    return value
  elseif kind == "bool" then
    if word == "true" or word == "1" then return true end
    if word == "false" or word == "0" then return false end
    return nil, "expects true, false, 1 or 0, got '" .. word .. "'"
  elseif kind == "enum" then
    if value_problem(param, word) then
      return nil, "expects one of " .. table.concat(param.values, "|") .. ", got '" .. word .. "'"
    end
    return word
  end
  local problem = value_problem(param, word)
  if problem then return nil, problem end
  return word
end

--- @param params ActionParam[]
--- @return integer
local function required_count(params)
  local count = 0
  for index, param in ipairs(params) do
    if param.default == nil then count = index end
  end
  return count
end

--- Fill trailing defaults and check the count. Raises with `where` as the prefix.
--- @param handle ActionHandle
--- @param given  any[]    Typed values (nil holes are not allowed)
--- @param count  integer
--- @param check  fun(param: ActionParam, index: integer, value: any): any  Validates and returns the value
--- @return any[]
local function complete_args(handle, given, count, check)
  local params = handle.params
  local where = "action '" .. handle.id .. "'"
  if count > #params then error(where .. " takes at most " .. #params .. " argument(s), got " .. count, 0) end
  if count < required_count(params) then
    error(where .. " needs at least " .. required_count(params) .. " argument(s), got " .. count, 0)
  end
  local values = {}
  for index, param in ipairs(params) do
    if index <= count then
      values[index] = check(param, index, given[index])
    else
      values[index] = param.default
    end
  end
  return values
end

--- @param handle ActionHandle
--- @param given  any[]
--- @param count  integer
--- @return any[]
local function check_values(handle, given, count)
  return complete_args(handle, given, count, function(param, index, value)
    local problem = value_problem(param, value)
    if problem then
      error("action '" .. handle.id .. "' param " .. index .. " (" .. param.name .. ") " .. problem, 0)
    end
    return value
  end)
end

---------------------------------------------------------------------------------------------------
-- Ipc and Cmd: runnable data
---------------------------------------------------------------------------------------------------

--- Single-quote a word for the shell unless it is plain.
--- @param word string
--- @return string
local function shell_word(word)
  if word:match("^[%w_%-%./=:,+@]+$") then return word end
  return "'" .. word:gsub("'", "'\\''") .. "'"
end

--- @param value any  A typed param value
--- @return string
local function render_value(value)
  if type(value) == "number" then
    if value % 1 == 0 and math.abs(value) < MAX_SAFE_INT then return string.format("%d", value) end
    return string.format("%.14g", value)
  end
  return tostring(value)
end

--- Replace every `{name}` in `template` from `values` in one pass: a value that itself holds `{other}` stays text.
--- A name with no value is left as written.
--- @param template string
--- @param values   table<string, any>
--- @return string
local function render(template, values)
  return (
    template:gsub("{([a-z][a-z0-9_]*)}", function(name)
      if values[name] == nil then return nil end
      return render_value(values[name])
    end)
  )
end

--- The `{name}` placeholders a word mentions.
--- @param word string
--- @return string[]
local function placeholders(word)
  local names = {}
  for name in word:gmatch("{([a-z][a-z0-9_]*)}") do
    table.insert(names, name)
  end
  return names
end

--- Hand a finished command line to Hyprland. Replaceable by tests.
--- @param command string
function Act.exec(command) hl.dispatch(hl.dsp.exec_cmd(command)) end

--- Every word quoted for the shell: arguments cannot split, expand or start a second command. Only the program, a
--- fixed word that may start with `~/`, is left for the shell to expand; `~` anywhere else stays literal.
--- @param words string[]
--- @param values table<string, any>
--- @return string
local function command_line(words, values)
  local quoted = {}
  for index, word in ipairs(words) do
    local text = render(word, values)
    local home, rest = text:match("^(~/)(.*)$")
    if index == 1 and home then
      table.insert(quoted, home .. shell_word(rest))
    else
      table.insert(quoted, shell_word(text))
    end
  end
  return table.concat(quoted, " ")
end

local runnable = {}
runnable.__index = runnable
runnable.__call = function(self, values) Act.exec(self:command(values or {})) end

--- The shell command this performs, with `{name}` words filled from `values`.
--- @param values table<string, any>|nil
--- @return string
function runnable:command(values) return command_line(self:words(), values or {}) end

--- A bar IPC call: `qs-ipc call <target> <fn> <args...>`. Carries its data so a later check can verify the
--- target function exists. Args may hold `{param}` placeholders.
--- @param target string
--- @param fn     string
--- @param ...    string
--- @return table
function Act.Ipc(target, fn, ...)
  local this = setmetatable({ kind = "ipc", target = target, ["function"] = fn, args = { ... } }, runnable)
  function this:words()
    local words = { Scripts.qs_ipc, "call", self.target, self["function"] }
    for _, arg in ipairs(self.args) do
      table.insert(words, arg)
    end
    return words
  end
  return this
end

--- A program run by argv. Carries its data for the registry check. Words may hold `{param}` placeholders.
--- @param ... string  Program, then its arguments
--- @return table
function Act.Cmd(...)
  local this = setmetatable({ kind = "command", argv = { ... } }, runnable)
  function this:words() return self.argv end
  return this
end

---------------------------------------------------------------------------------------------------
-- define / bind
---------------------------------------------------------------------------------------------------

--- @param spec any
--- @return ActionKey|nil key, string|nil problem
local function normalize_key(spec)
  if type(spec) == "string" then spec = { key = spec } end
  if type(spec) ~= "table" or type(spec.key) ~= "string" or spec.key == "" then
    return nil, "a key is a non-empty string or {key = string, leader?, universal?}"
  end
  return { key = spec.key, leader = spec.leader == true, universal = spec.universal == true }
end

--- @param params any
--- @return ActionParam[]|nil copy, string|nil problem
local function normalize_params(params)
  if params == nil then return {} end
  if type(params) ~= "table" then return nil, "params must be a list" end

  local copy, seen, defaulted = {}, {}, false
  for index, param in ipairs(params) do
    if type(param) ~= "table" or type(param.name) ~= "string" or not param.name:match(NAME_PATTERN) then
      return nil, "param " .. index .. " needs a name like 'count'"
    end
    if seen[param.name] then return nil, "param '" .. param.name .. "' is declared twice" end
    seen[param.name] = true
    if not PARAM_TYPES[param.type] then
      return nil,
        "param '" .. param.name .. "' has type '" .. tostring(param.type) .. "'; use int, float, string, bool or enum"
    end
    local entry = { name = param.name, type = param.type, values = param.values, default = param.default }
    if param.type == "enum" then
      local ok = type(param.values) == "table" and #param.values > 0
      for _, member in ipairs(ok and param.values or {}) do
        ok = ok and type(member) == "string" and member ~= ""
      end
      if not ok then return nil, "enum param '" .. param.name .. "' needs a list of string values" end
    elseif param.values ~= nil then
      return nil, "param '" .. param.name .. "' has values but is not an enum"
    end
    if param.default ~= nil then
      defaulted = true
      local problem = value_problem(entry, param.default)
      if problem then return nil, "default of '" .. param.name .. "' " .. problem end
    elseif defaulted then
      return nil, "param '" .. param.name .. "' has no default after one that has; defaults go last"
    end
    table.insert(copy, entry)
  end
  return copy
end

--- Every `{name}` an Ipc/Cmd uses must be a declared param, or it would reach the program as literal text.
--- @param run    table
--- @param params ActionParam[]
--- @return string|nil problem
local function placeholder_problem(run, params)
  local declared = {}
  for _, param in ipairs(params) do
    declared[param.name] = true
  end
  local words = run:words()
  if #placeholders(words[1] or "") > 0 then return "the program word '" .. words[1] .. "' cannot hold a placeholder" end
  for _, word in ipairs(words) do
    for _, name in ipairs(placeholders(word)) do
      if not declared[name] then return "'" .. word .. "' uses {" .. name .. "}, which is not a declared param" end
    end
  end
  return nil
end

--- @param run any
--- @return boolean
local function is_runnable(run)
  if type(run) == "function" then return true end
  local meta = type(run) == "table" and getmetatable(run) or nil
  return meta == runnable
end

--- Register one key for an action's handle.
--- @param handle ActionHandle
--- @param key    ActionKey
--- @param opts   table   Extra hl.bind options
--- @param args   any[]   Checked, defaults filled
local function register_key(handle, key, opts, args)
  local bind_opts = {}
  for k, v in pairs(handle.opts) do
    -- A define's opts never rename its keys: the label does, and only Act.bind can give one key its own.
    if k ~= "desc" then bind_opts[k] = v end
  end
  for k, v in pairs(opts) do
    bind_opts[k] = v
  end
  if bind_opts.submap_universal == nil and key.universal then bind_opts.submap_universal = true end
  -- A key shown under its own name ("Focus Left") or hidden from which-key (`desc = false`, a second key for the same
  -- thing) says so in `desc`; the label names the action.
  local desc = handle.label
  if bind_opts.desc ~= nil then desc = bind_opts.desc or nil end
  bind_opts.desc = nil
  local register = key.leader and Bind.leader_key or Bind.key
  local made = register(key.key, function() Act.run(handle.id, table.unpack(args)) end, desc, bind_opts)
  -- Recorded only after the bind succeeded, so list never shows a key that failed to register.
  local bound = key.leader and Bind.leader and Bind.leader ~= "" and (Bind.leader .. " + " .. key.key) or key.key
  table.insert(
    handle.bound_keys,
    { key = bound, leader = key.leader, universal = key.universal, submap = Bind.current_submap(), bind = made[1] }
  )
end

--- Put every non-key option except those Act.bind owns into a fresh table.
--- @param opts table
--- @return table
local function passthrough_opts(opts)
  local copy = {}
  for k, v in pairs(opts) do
    if k ~= "key" and k ~= "args" then copy[k] = v end
  end
  return copy
end

--- Bind a key to an action that is already defined.
--- @param id   string
--- @param opts { key: string|table, args: any[]|nil, desc: string|false|nil }  `desc` replaces the label on this key,
---             false leaves it undescribed; any other field goes to hl.bind
function Act.bind(id, opts)
  local handle = registry[tostring(id)]
  if not handle then
    warn("Act.bind: unknown action id '" .. tostring(id) .. "'")
    return
  end
  opts = opts or {}

  local key, key_problem = normalize_key(opts.key)
  if not key then
    warn("Act.bind '" .. id .. "': " .. key_problem)
    return
  end
  local given = opts.args or {}
  local args_ok, args = pcall(check_values, handle, given, #given)
  if not args_ok then
    warn("Act.bind: " .. tostring(args))
    return
  end

  local bound_ok, bound_err = pcall(register_key, handle, key, passthrough_opts(opts), args)
  if not bound_ok then warn("Act.bind '" .. id .. "': " .. tostring(bound_err)) end
end

--- Validate a spec into a handle, or return why it cannot be one.
--- @param id   string
--- @param spec table
--- @return ActionHandle|nil handle, string|nil problem
local function build_handle(id, spec)
  if type(id) ~= "string" or not id:match(ID_PATTERN) then return nil, "ids look like 'zoom.toggle'" end
  if registry[id] then return nil, "already defined" end
  if type(spec) ~= "table" then return nil, "needs a spec table" end
  if type(spec.label) ~= "string" or spec.label == "" then return nil, "needs a label" end
  if spec.intent ~= nil and type(spec.intent) ~= "string" then return nil, "intent must be a string" end
  if not is_runnable(spec.run) then return nil, "run must be a function, Act.Ipc(...) or Act.Cmd(...)" end

  local params, params_problem = normalize_params(spec.params)
  if not params then return nil, params_problem end
  if type(spec.run) == "table" then
    local problem = placeholder_problem(spec.run, params)
    if problem then return nil, problem end
  end

  local handle = {
    id = id,
    label = spec.label,
    intent = spec.intent,
    params = params,
    extra_keys = {},
    opts = spec.opts or {},
    bound_keys = {},
    run = spec.run,
  }
  if spec.key ~= nil then
    local key, key_problem = normalize_key(spec.key)
    if not key then return nil, key_problem end
    handle.key = key
  end
  for _, extra in ipairs(spec.extra_keys or {}) do
    local key, key_problem = normalize_key(extra)
    if not key then return nil, key_problem end
    table.insert(handle.extra_keys, key)
  end
  if (handle.key or #handle.extra_keys > 0) and required_count(params) > 0 then
    return nil, "a default key cannot supply required params; define it keyless and use Act.bind with args"
  end
  return handle
end

--- Declare an action and bind its default key and extra keys. Any problem warns and skips this action only.
--- @param id   string
--- @param spec { label: string, intent: string|nil, params: ActionParam[]|nil, key: string|table|nil, extra_keys: table[]|nil, opts: table|nil, run: function|table }
--- @return ActionHandle|nil
function Act.define(id, spec)
  local built_ok, handle, problem = pcall(build_handle, id, spec)
  if not built_ok then
    handle, problem = nil, tostring(handle)
  end
  if not handle then
    warn("Act.define '" .. tostring(id) .. "': " .. problem)
    return nil
  end

  registry[handle.id] = handle
  local default_keys = {}
  if handle.key then table.insert(default_keys, handle.key) end
  for _, extra in ipairs(handle.extra_keys) do
    table.insert(default_keys, extra)
  end
  for _, key in ipairs(default_keys) do
    Act.bind(handle.id, { key = key })
  end
  return handle
end

---------------------------------------------------------------------------------------------------
-- run
---------------------------------------------------------------------------------------------------

--- @param handle ActionHandle
--- @param values any[]  Typed, defaults filled
local function perform(handle, values)
  if type(handle.run) == "function" then return handle.run(table.unpack(values, 1, #handle.params)) end
  local named = {}
  for index, param in ipairs(handle.params) do
    named[param.name] = values[index]
  end
  return handle.run(named)
end

--- @param id any
--- @return ActionHandle
local function lookup(id)
  local handle = registry[tostring(id)]
  if not handle then error("unknown action '" .. tostring(id) .. "'", 0) end
  return handle
end

--- Perform an action with typed Lua values. Raises on an unknown id or a bad argument.
--- @param id  string
--- @param ... any
function Act.run(id, ...)
  local handle = lookup(id)
  return perform(handle, check_values(handle, { ... }, select("#", ...)))
end

--- Perform an action from command-line words (all strings), parsed to each param's type. Raises on an unknown id,
--- a bad word or the wrong count, so `hyprctl eval` exits non-zero and the message reaches the caller.
--- @param id    string
--- @param words string[]
function Act.run_cli(id, words)
  local handle = lookup(id)
  if type(words) ~= "table" then error("run_cli expects a list of strings", 0) end
  for index = 1, #words do
    if type(words[index]) ~= "string" then error("run_cli argument " .. index .. " is not a string", 0) end
  end
  local values = complete_args(handle, words, #words, function(param, index, word)
    local value, problem = parse_word(param, word)
    if problem then
      error("action '" .. handle.id .. "' param " .. index .. " (" .. param.name .. ") " .. problem, 0)
    end
    return value
  end)
  return perform(handle, values)
end

---------------------------------------------------------------------------------------------------
-- list
---------------------------------------------------------------------------------------------------

--- Every defined action, sorted by id.
--- @return ActionHandle[]
function Act.list()
  local handles = {}
  for _, handle in pairs(registry) do
    table.insert(handles, handle)
  end
  table.sort(handles, function(a, b) return a.id < b.id end)
  return handles
end

--- @param run function|table
--- @return table
local function perform_entry(run)
  if type(run) == "function" then return { kind = "lua" } end
  if run.kind == "ipc" then
    return {
      kind = "ipc",
      target = run.target,
      ["function"] = run["function"],
      args = Json.array({ table.unpack(run.args) }),
    }
  end
  return { kind = "command", argv = Json.array({ table.unpack(run.argv) }) }
end

--- @param handle ActionHandle
--- @return table
local function list_entry(handle)
  local params = Json.array()
  for _, param in ipairs(handle.params) do
    table.insert(params, { name = param.name, type = param.type, values = param.values, default = param.default })
  end
  local keys = Json.array()
  for _, entry in ipairs(handle.bound_keys) do
    -- A key removed with Bind.unbind is no longer a key of the action. The submap field is left out for the global map.
    if Bind.is_bound(entry.key, entry.submap, entry.bind) then
      table.insert(keys, {
        key = entry.key,
        leader = entry.leader,
        universal = entry.universal,
        submap = entry.submap ~= "" and entry.submap or nil,
      })
    end
  end
  return {
    id = handle.id,
    label = handle.label,
    intent = handle.intent == nil and Json.null or handle.intent,
    params = params,
    keys = keys,
    perform = perform_entry(handle.run),
  }
end

--- The list as the JSON `hypr-act list` prints: {"version":1,"actions":[{id,label,intent,params,keys,perform}]},
--- sorted by id. `intent` is null when the action has none.
--- @return string
function Act.list_json()
  local actions = Json.array()
  for _, handle in ipairs(Act.list()) do
    table.insert(actions, list_entry(handle))
  end
  return Json.encode({ version = 1, actions = actions })
end

--- Write the list to `path`. `hyprctl eval` returns only "ok", so the hypr-act script reads the answer from this file.
--- @param path string
function Act.write_list(path)
  local file = assert(io.open(path, "w"))
  file:write(Act.list_json(), "\n")
  file:close()
end

return Act
