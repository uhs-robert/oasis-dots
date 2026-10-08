-- home/hypr/.config/hypr/lib/json.lua

--- @class Json
local Json = {}

local ESCAPES = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

local function skip(str, pos) return str:find("[^ \t\r\n]", pos) or #str + 1 end

local parse_value

local function parse_string(str, pos)
  local out = {}
  pos = pos + 1
  while true do
    local ch = str:sub(pos, pos)
    if ch == "" then error("unterminated string") end
    if ch == '"' then return table.concat(out), pos + 1 end
    if ch == "\\" then
      local esc = str:sub(pos + 1, pos + 1)
      if esc == "u" then
        local hex = str:match("^%x%x%x%x", pos + 2)
        if not hex then error("bad unicode escape") end
        out[#out + 1] = utf8.char(tonumber(hex, 16))
        pos = pos + 6
      elseif ESCAPES[esc] then
        out[#out + 1] = ESCAPES[esc]
        pos = pos + 2
      else
        error("bad escape")
      end
    else
      out[#out + 1] = ch
      pos = pos + 1
    end
  end
end

local function parse_container(str, pos, close, is_object)
  local out = {}
  pos = skip(str, pos + 1)
  if str:sub(pos, pos) == close then return out, pos + 1 end
  while true do
    local key
    if is_object then
      if str:sub(pos, pos) ~= '"' then error("expected key") end
      key, pos = parse_string(str, pos)
      pos = skip(str, pos)
      if str:sub(pos, pos) ~= ":" then error("expected colon") end
      pos = skip(str, pos + 1)
    end
    local value
    value, pos = parse_value(str, pos)
    if is_object then
      out[key] = value
    else
      out[#out + 1] = value
    end
    pos = skip(str, pos)
    local ch = str:sub(pos, pos)
    if ch == close then return out, pos + 1 end
    if ch ~= "," then error("expected comma") end
    pos = skip(str, pos + 1)
  end
end

parse_value = function(str, pos)
  local ch = str:sub(pos, pos)
  if ch == "{" then return parse_container(str, pos, "}", true) end
  if ch == "[" then return parse_container(str, pos, "]", false) end
  if ch == '"' then return parse_string(str, pos) end
  local num = str:match("^-?%d+%.?%d*[eE]?[+-]?%d*", pos)
  if num and num ~= "" then return tonumber(num) or error("bad number"), pos + #num end
  for word, value in pairs({ ["true"] = true, ["false"] = false }) do
    if str:sub(pos, pos + #word - 1) == word then return value, pos + #word end
  end
  if str:sub(pos, pos + 3) == "null" then return nil, pos + 4 end
  error("unexpected token")
end

--- Decode a JSON document; returns nil when it is malformed.
--- @param str string
--- @return any
function Json.decode(str)
  local ok, value, pos = pcall(function()
    local v, p = parse_value(str, skip(str, 1))
    return v, p
  end)
  if not ok or skip(str, pos) <= #str then return nil end
  return value
end

local ENCODE_ESCAPES =
  { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function encode_string(str)
  local escaped = str:gsub('[%c"\\]', function(ch) return ENCODE_ESCAPES[ch] or string.format("\\u%04x", ch:byte()) end)
  return '"' .. escaped .. '"'
end

--- Metatable tagging a table that must encode as a JSON array even when empty.
local ARRAY_MT = {}

local function is_array(tbl)
  if getmetatable(tbl) == ARRAY_MT then return true end
  local count = 0
  for _ in pairs(tbl) do
    count = count + 1
  end
  return count > 0 and count == #tbl
end

local function encode_value(value)
  local kind = type(value)
  if kind == "string" then return encode_string(value) end
  if kind == "number" then
    return value == math.floor(value) and string.format("%d", value) or string.format("%.14g", value)
  end
  if kind == "boolean" then return tostring(value) end
  if kind ~= "table" then return "null" end
  local parts = {}
  if is_array(value) then
    for _, item in ipairs(value) do
      parts[#parts + 1] = encode_value(item)
    end
    return "[" .. table.concat(parts, ",") .. "]"
  end
  local keys = {}
  for key in pairs(value) do
    keys[#keys + 1] = tostring(key)
  end
  table.sort(keys)
  for _, key in ipairs(keys) do
    parts[#parts + 1] = encode_string(key) .. ":" .. encode_value(value[key])
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

--- Marks `tbl` (default a new table) to encode as a JSON array, so an empty one becomes `[]` rather than `{}`.
--- @param tbl table|nil
--- @return table
function Json.array(tbl) return setmetatable(tbl or {}, ARRAY_MT) end

--- Encode a table, string, number or boolean as compact JSON with sorted object keys.
--- An empty table becomes `{}` unless marked with `Json.array`.
--- @param value any
--- @return string
function Json.encode(value) return encode_value(value) end

return Json
