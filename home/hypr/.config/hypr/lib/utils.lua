-- home/hypr/.config/hypr/lib/utils.lua

--- @class Utils
local Utils = {}

--- Returns true if t is a sequence (array-like: all integer keys 1..n).
local function is_array(t)
  local n = 0
  for _ in pairs(t) do
    n = n + 1
  end
  return n == #t and n > 0
end

--- Deep-merge one or more source tables into target. Arrays are replaced, not merged.
--- @param target table
--- @param ... table
--- @return table
Utils.deep_extend = function(target, ...)
  for _, source in ipairs({ ... }) do
    for k, v in pairs(source) do
      if type(v) == "table" and type(target[k]) == "table" and not is_array(v) then
        Utils.deep_extend(target[k], v)
      else
        target[k] = v
      end
    end
  end
  return target
end

--- Writes content to a file, creating or overwriting it. Returns true on success.
--- @param path string
--- @param content string
--- @return boolean
Utils.write_file = function(path, content)
  local f = io.open(path, "w")
  if not f then return false end
  f:write(content)
  f:close()
  return true
end

return Utils
