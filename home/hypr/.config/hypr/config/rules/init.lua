-- home/hypr/.config/hypr/config/system/rules.lua

--- @class Rules
--- @field layer_rules table<string, any> Registry of named layer-rule handles (supports set_enabled/is_enabled).
local Rules = {}

--- Registers bezier curves and animation definitions for windows, workspaces, fade, and layers.
local set_animations = function()
  -- https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/
  hl.curve("smooth", { type = "bezier", points = { { 0.22, 1 }, { 0.1, 1.1 } } })
  hl.curve("quick", { type = "bezier", points = { { 0.15, 0.85 }, { 0.25, 1.0 } } })
  hl.curve("overshot", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.08 } } })
  hl.curve("linearish", { type = "bezier", points = { { 0.3, 0.0 }, { 0.7, 1.0 } } })
  hl.curve("easeOutQuint", { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } })

  -- WINDOWS
  hl.animation({ leaf = "windows", enabled = true, speed = 4, bezier = "smooth", style = "popin 95%" })
  hl.animation({ leaf = "windowsIn", enabled = true, speed = 4, bezier = "smooth", style = "popin 85%" })
  hl.animation({ leaf = "windowsOut", enabled = true, speed = 3, bezier = "quick", style = "popin 90%" })
  hl.animation({ leaf = "windowsMove", enabled = true, speed = 3, bezier = "quick" })

  -- WORKSPACES
  hl.animation({ leaf = "workspaces", enabled = true, speed = 5, bezier = "smooth", style = "slidefade 20%" })
  hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 3, bezier = "smooth", style = "slidefadevert 5%" })

  -- LAYERS
  hl.animation({ leaf = "layers", enabled = true, speed = 3, bezier = "quick", style = "fade" })
  hl.animation({ leaf = "layersIn", enabled = true, speed = 3, bezier = "quick" })
  hl.animation({ leaf = "layersOut", enabled = true, speed = 3, bezier = "quick" })
  hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 5, bezier = "quick" })
  hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 3, bezier = "linearish" })

  -- FADE
  hl.animation({ leaf = "fade", enabled = true, speed = 4, bezier = "smooth" })
end

--- Applies animation layer rules for shell surfaces (waybar, rofi, notifications, etc.).
--- Returns a registry table mapping rule name -> rule handle (supports set_enabled / is_enabled).
--- @return table<string, any>
local set_layer_rules = function()
  -- https://wiki.hypr.land/Configuring/Basics/Window-Rules/#layer-rules
  local rules = {}
  local function register(spec)
    local handle = hl.layer_rule(spec)
    rules[spec.name] = handle

    return handle
  end

  -- stylua: ignore start
  register({ name = "waybar",            match = { namespace = "waybar" },            animation = "slide top" })
  register({ name = "rofi",              match = { namespace = "rofi" },              animation = "slide" })
  register({ name = "hyprpaper",         match = { namespace = "hyprpaper" },         animation = "fade" })
  register({ name = "selection",         match = { namespace = "selection" },         animation = "fade" })
  register({ name = "notificationsmenu", match = { namespace = "notificationsmenu" }, animation = "slide right" })
  register({ name = "dashboardmenu",     match = { namespace = "dashboardmenu" },     animation = "slide left" })

  -- Conditionally enabled
  register({ name = "no_animation",      match = { namespace = ".*"},                 no_anim = true})
  -- stylua: ignore end

  rules.no_animation:set_enabled(false)

  return rules
end

--- Applies workspace rules.
local set_workspace_rules = function() return nil end

--- Applies window rules: opacity, float, pin, XWayland fixes, and per-app overrides.
local set_window_rules = function()
  -- https://wiki.hypr.land/Configuring/Basics/Window-Rules/#window-rules
  hl.window_rule({ name = "suppress-maximize-events", match = { class = ".*" }, suppress_event = "maximize" })
  hl.window_rule({
    name = "fix-xwayland-dragging",
    match = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
    no_focus = true,
  })
  hl.window_rule({
    name = "float-class",
    match = { class = "^(float|thunar|qalculate-gtk)$" },
    float = true,
    size = "(monitor_w*0.8) (monitor_h*0.8)",
    dim_around = true,
  })
  hl.window_rule({
    name = "float-title",
    match = { title = "^(ProtonPlus)$" },
    float = true,
    size = "(monitor_w*0.8) (monitor_h*0.8)",
    dim_around = true,
  })
  hl.window_rule({ name = "fix-dropdown-opacity", match = { float = true }, opacity = "1.0 1.0 override" })

  -- Browsers
  hl.window_rule({
    name = "firefox-opacity",
    match = { class = "^(org\\.mozilla\\.firefox)$" },
    opacity = "1.0 override 0.85 override",
  })
  hl.window_rule({
    name = "qutebrowser-opacity",
    match = { class = "^(org\\.qutebrowser\\.qutebrowser)$" },
    opacity = "1.0 override 0.85 override",
  })

  -- Rofi
  hl.window_rule({ match = { title = "^(rofiMenu)$" }, opacity = "1.0 1.0 override" })

  -- nvim-wl-anywhere
  hl.window_rule({
    match = { class = "^nvim-wl-anywhere" },
    float = true,
    pin = true,
    stay_focused = true,
    size = "(monitor_w*0.7) (monitor_h*0.7)",
  })
end

--- Toggles browser opacity when a screenshare session starts or stops.
--- Browsers dim when inactive by default; override to full opacity during capture.
local set_screenshare_handler = function()
  hl.on("screenshare.state", function(active, _type, _name)
    local opacity = active and "1.0 1.0 override" or "1.0 override 0.85 override"
    hl.window_rule({
      name = "firefox-opacity",
      match = { class = "^(org\\.mozilla\\.firefox)$" },
      opacity = opacity,
    })
    hl.window_rule({
      name = "qutebrowser-opacity",
      match = { class = "^(org\\.qutebrowser\\.qutebrowser)$" },
      opacity = opacity,
    })
  end)
end

--- @param name string
--- @return any|nil
function Rules.get(name) return Rules.layer_rules[name] end

--- @param name string
function Rules.enable(name)
  local r = Rules.layer_rules[name]
  if r then r:set_enabled(true) end

  return hl.dsp.no_op()
end

--- @param name string
function Rules.disable(name)
  local r = Rules.layer_rules[name]
  if r then r:set_enabled(false) end

  return hl.dsp.no_op()
end

--- @param name string
function Rules.toggle(name)
  local r = Rules.layer_rules[name]
  if r then r:set_enabled(not r:is_enabled()) end

  return hl.dsp.no_op()
end

--- @param name string
--- @param cmd string
function Rules.exec_without_layer_rule(name, cmd)
  local rule = Rules.layer_rules[name]
  if rule then rule:set_enabled(false) end

  return hl.dsp.exec_cmd(string.format([[sh -c '%s; hyprctl dispatch "LayerRules.enable('\''%s'\'')"']], cmd, name))
end

--- Enables a named rule, runs cmd, then disables the rule after cmd exits.
--- @param name string
--- @param cmd string
--- @return any
function Rules.exec_with_layer_rule(name, cmd)
  local rule = Rules.layer_rules[name]
  if rule then rule:set_enabled(true) end

  return hl.dsp.exec_cmd(
    string.format([[sh -c '%s; status=$?; hyprctl dispatch "LayerRules.disable('\''%s'\'')"; exit $status']], cmd, name)
  )
end

--- @param cmd string
--- @return any
function Rules.exec_without_layer_animations(cmd)
  local name = "no_animation"
  local rule = Rules.layer_rules[name]
  if rule then rule:set_enabled(true) end

  return hl.dsp.exec_cmd(
    string.format([[sh -c '%s; status=$?; hyprctl dispatch "LayerRules.disable('\''%s'\'')"; exit $status']], cmd, name)
  )
end

-- Global functions which are accessible externally via `hyprctl dispatch "LayerRules"`
_G.LayerRules = {
  enable = function(name) return Rules.enable(name) end,
  disable = function(name) return Rules.disable(name) end,
  toggle = function(name) return Rules.toggle(name) end,
  exec_with = function(name, cmd) return Rules.exec_with_layer_rule(name, cmd) end,
  exec_without = function(name, cmd) return Rules.exec_without_layer_rule(name, cmd) end,
  exec_without_animation = function(cmd) return Rules.exec_without_layer_animations(cmd) end,
}

local function init()
  set_animations()
  Rules.layer_rules = set_layer_rules()
  set_workspace_rules()
  set_window_rules()
  set_screenshare_handler()
end

init()

return Rules
