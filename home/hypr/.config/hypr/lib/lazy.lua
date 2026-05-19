--- @class Lazy
local Lazy = {}

--- @class LazyEntry
--- @field mod string
--- @field loaded table|nil
--- @field proxy table|nil

--- @type table<string, LazyEntry>
local REGISTRY = {}

--- @param entry LazyEntry
--- @return table
local function resolve(entry)
  entry.loaded = entry.loaded or require(entry.mod)
  return entry.loaded
end

--- @param mod string
--- @return table
function Lazy.load(mod)
  assert(type(mod) == "string", "Lazy.load(mod): mod must be a string")

  if REGISTRY[mod] then return REGISTRY[mod].proxy end

  local entry = { mod = mod }
  local proxy = {}

  entry.proxy = setmetatable(proxy, {
    __index = function(t, key)
      local val = resolve(entry)[key]

      if type(val) ~= "function" then return val end

      local fn = function(...) return resolve(entry)[key](...) end

      rawset(t, key, fn)
      return fn
    end,
  })

  REGISTRY[mod] = entry

  return proxy
end

return Lazy
