--- Keyboard, mouse and touchpad options from Config.input, with the Settings panel's choices in
--- ~/.local/state/hypr/input.json winning over the machine profile.

local Json = require("lib.json") ---@class Json
local State = require("lib.state")

local Input = {}

-- Accepts integral floats too (the bar accepts 25.0 and 1e2, which lib.json decodes as floats) and returns the integer to use.
local function integer_in(min, max)
  return function(v)
    local whole = type(v) == "number" and math.tointeger(v)
    if whole and whole >= min and whole <= max then return true, whole end
    return false
  end
end

local function is_boolean(v) return type(v) == "boolean" end

-- Saved keys and the check each value must pass; anything else in the file is ignored.
local VALID = {
  kb_layout = function(v) return type(v) == "string" and v:match("^[%w_,-]+$") ~= nil end,
  kb_variant = function(v) return type(v) == "string" and v:match("^[%w_,-]*$") ~= nil end,
  repeat_rate = integer_in(1, 100),
  repeat_delay = integer_in(100, 2000),
  sensitivity = function(v) return type(v) == "number" and v >= -1 and v <= 1 end,
  follow_mouse = integer_in(0, 3),
  natural_scroll = is_boolean,
  tap_to_click = is_boolean,
  disable_while_typing = is_boolean,
  which_key_delay_ms = integer_in(0, 5000),
  pointer_keys = function(v) return v == "hjkl" or v == "wasd" or v == "both" end,
}

--- Settings panel choices, validated; a missing or malformed file yields none.
--- @return table
function Input.state()
  local file = io.open(State() .. "/input.json", "r")
  if not file then return {} end
  local text = file:read("*a")
  file:close()

  local ok, data = pcall(Json.decode, text)
  if not ok or type(data) ~= "table" then return {} end
  local out = {}
  for key, valid in pairs(VALID) do
    local accepted, normalized = valid(data[key])
    if accepted then
      if normalized == nil then normalized = data[key] end
      out[key] = normalized
    end
  end
  return out
end

--- The `input` table for hl.config.
--- @param input Config.Input
--- @return table
function Input.options(input)
  return {
    numlock_by_default = false,
    kb_layout = input.kb_layout,
    kb_variant = input.kb_variant or "",
    kb_options = input.kb_options or "",
    repeat_rate = input.repeat_rate,
    repeat_delay = input.repeat_delay,
    follow_mouse = input.follow_mouse,
    mouse_refocus = false,
    sensitivity = input.sensitivity,
    touchpad = {
      natural_scroll = input.natural_scroll,
      tap_to_click = input.tap_to_click,
      disable_while_typing = input.disable_while_typing,
    },
  }
end

--- Re-reads the saved choices and applies them live; the Settings panel calls this through `hyprctl eval`.
--- The which-key delay and the pointer keys are read once at load, so a change to them needs `hyprctl reload` instead.
function Input.apply()
  local Config = require("config")
  for key, value in pairs(Input.state()) do
    Config.input[key] = value
  end
  hl.config({ input = Input.options(Config.input) })
end

return Input
