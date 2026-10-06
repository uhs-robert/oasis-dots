-- home/hypr/.config/hypr/config/input/init.lua
--- Keyboard, mouse and touchpad options from Config.input, with the Settings panel's choices in
--- ~/.local/state/hypr/input.json winning over the machine profile.

local Json = require("lib.json") ---@class Json
local State = require("lib.state")

local Input = {}

local function integer_in(min, max)
  return function(v) return math.type(v) == "integer" and v >= min and v <= max end
end

local function is_boolean(v) return type(v) == "boolean" end

-- Saved keys and the check each value must pass; anything else in the file is ignored.
local VALID = {
  kb_layout = function(v) return type(v) == "string" and v:match("^[%w_,-]+$") ~= nil end,
  kb_variant = function(v) return type(v) == "string" and v:match("^[%w_,-]*$") ~= nil end,
  caps_escape = is_boolean,
  repeat_rate = integer_in(1, 100),
  repeat_delay = integer_in(100, 2000),
  sensitivity = function(v) return type(v) == "number" and v >= -1 and v <= 1 end,
  follow_mouse = integer_in(0, 3),
  natural_scroll = is_boolean,
  tap_to_click = is_boolean,
  disable_while_typing = is_boolean,
  which_key_delay_ms = integer_in(0, 5000),
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
    if valid(data[key]) then out[key] = data[key] end
  end
  return out
end

--- XKB options with Caps Lock as Escape forced on or off; nil leaves the profile's options alone.
--- Turning it on drops any other `caps:` option, since XKB applies only one.
--- @param options string|nil
--- @param caps_escape boolean|nil
--- @return string
function Input.kb_options(options, caps_escape)
  if caps_escape == nil then return options or "" end
  local kept = {}
  for opt in (options or ""):gmatch("[^,]+") do
    if not (opt == "caps:escape" or (caps_escape and opt:match("^caps:"))) then kept[#kept + 1] = opt end
  end
  if caps_escape then kept[#kept + 1] = "caps:escape" end
  return table.concat(kept, ",")
end

--- The `input` table for hl.config.
--- @param input Config.Input
--- @return table
function Input.options(input)
  return {
    numlock_by_default = false,
    kb_layout = input.kb_layout,
    kb_variant = input.kb_variant or "",
    kb_options = Input.kb_options(input.kb_options, input.caps_escape),
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
--- The which-key delay is read once by HyprVim's setup, so a change to it needs `hyprctl reload` instead.
function Input.apply()
  local Config = require("config")
  for key, value in pairs(Input.state()) do
    Config.input[key] = value
  end
  hl.config({ input = Input.options(Config.input) })
end

return Input
