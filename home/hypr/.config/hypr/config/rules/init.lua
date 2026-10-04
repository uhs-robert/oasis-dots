-- home/hypr/.config/hypr/config/rules/init.lua

--- @class Rules
--- @field layer_rules table<string, any> Registry of named layer-rule handles (supports set_enabled/is_enabled).
--- @field window_rules table<string, any> Registry of named window-rule handles (supports set_enabled/is_enabled).
local Rules = {}

local FADE_SPEED = 4

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
  hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 3, bezier = "linearish" })
  hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 3, bezier = "linearish" })

  -- FADE
  hl.animation({ leaf = "fade", enabled = true, speed = FADE_SPEED, bezier = "smooth" })
end

--- Applies animation layer rules for shell surfaces (rofi, notifications, etc.).
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
  register({ name = "rofi",              match = { namespace = "rofi" },              animation = "slide" })
  register({ name = "hyprpaper",         match = { namespace = "hyprpaper" },         animation = "fade" })
  register({ name = "selection",         match = { namespace = "selection" },         animation = "fade" })
  register({ name = "notificationsmenu", match = { namespace = "notificationsmenu" }, animation = "slide right" })
  register({ name = "dashboardmenu",     match = { namespace = "dashboardmenu" },     animation = "slide left" })
  register({ name = "quickshell_submap", match = { namespace = "quickshell-submap" }, no_anim = true })
  register({ name = "quickshell_popup",  match = { namespace = "quickshell-popup" },  no_anim = true })
  register({ name = "quickshell_osd",    match = { namespace = "quickshell-osd" },    no_anim = true })
  register({ name = "quickshell_whichkey", match = { namespace = "quickshell-whichkey" }, no_anim = true })
  register({ name = "quickshell_region", match = { namespace = "quickshell-region" }, no_anim = true })
  register({ name = "quickshell_zoom",   match = { namespace = "quickshell-zoom" },   no_anim = true, no_screen_share = true })
  register({ name = "quickshell_zoom_reticle", match = { namespace = "quickshell-zoom-reticle" }, no_anim = true })

  -- Conditionally enabled
  register({ name = "rofi_popin",        match = { namespace = "rofi" },              animation = "popin 80%" })
  register({ name = "no_animation",      match = { namespace = ".*"},                 no_anim = true})
  -- stylua: ignore end

  rules.rofi_popin:set_enabled(false)
  rules.no_animation:set_enabled(false)

  return rules
end

--- Applies workspace rules.
local set_workspace_rules = function() return nil end

local BROWSER_OPACITY = "1.0 override 0.85 override"

local browser_rules = {
  { name = "firefox-opacity", class = "^(org\\.mozilla\\.firefox)$" },
  { name = "qutebrowser-opacity", class = "^(org\\.qutebrowser\\.qutebrowser)$" },
}

--- Applies window rules: opacity, float, pin, XWayland fixes, and per-app overrides.
--- Returns a registry table mapping rule name -> rule handle (supports set_enabled / is_enabled).
--- @return table<string, any>
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
  for _, browser in ipairs(browser_rules) do
    hl.window_rule({ name = browser.name, match = { class = browser.class }, opacity = BROWSER_OPACITY })
  end

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

  -- bottom-half-screen: generic terminal dropdown, slides up from bottom. Any command
  -- launched with `--class bottom-half-screen` gets this treatment.
  hl.window_rule({
    name = "bottom-half-screen",
    match = { class = "^bottom-half-screen$" },
    float = true,
    pin = true,
    stay_focused = true,
    size = "(monitor_w-4) (monitor_h*0.6)",
    move = "2 (monitor_h*0.4)",
    animation = "slide bottom",
  })

  -- Steam Games
  hl.window_rule({
    name = "steam-games",
    match = {
      class = "^steam_app_[0-9]+$",
    },
    focus_on_activate = true,
    fullscreen = true,
  })

  -- Last, so it beats the browser opacity overrides above.
  local rules = {}
  rules["capture-opaque"] = hl.window_rule({
    name = "capture-opaque",
    match = { class = ".*" },
    opacity = "1.0 override 1.0 override",
    enabled = false,
  })
  hl.window_rule({
    name = "shared-window",
    match = { tag = "shared" },
    opacity = "1.0 override 1.0 override",
    no_dim = true,
  })

  return rules
end

--- Tags a shared window so it shows opaque and undimmed; name is its title at share start.
--- @param active boolean
--- @param name string
local function tag_shared_window(active, name)
  for _, w in ipairs(hl.get_windows() or {}) do
    local tags = type(w.tags) == "table" and table.concat(w.tags, ",") or (w.tags or "")
    local tagged = string.find("," .. tags .. ",", ",shared,", 1, true) ~= nil
    if active and w.title == name then
      hl.dispatch(hl.dsp.window.tag({ window = "address:" .. w.address, tag = "+shared" }))
      return
    elseif not active and tagged then
      hl.dispatch(hl.dsp.window.tag({ window = "address:" .. w.address, tag = "-shared" }))
    end
  end
end

local shared_monitors = {}

--- Shows every window on a shared monitor opaque and undimmed while any share of it runs.
--- @param active boolean
--- @param name string
local function set_shared_monitor(active, name)
  local entry = shared_monitors[name] or { count = 0 }
  entry.count = math.max(0, entry.count + (active and 1 or -1))
  if entry.count > 0 and not entry.rule then
    entry.rule = hl.window_rule({
      name = "shared-monitor-" .. name,
      match = { workspace = "m[" .. name .. "]" },
      opacity = "1.0 override 1.0 override",
      no_dim = true,
    })
  elseif entry.count == 0 and entry.rule then
    entry.rule:set_enabled(false)
    entry.rule = nil
  end
  shared_monitors[name] = entry
end

--- Quickshell layers whose window thumbnails open toplevel captures of their own.
local thumbnail_layers = { "quickshell-overview", "quickshell-popup" }

--- @return boolean
local function thumbnails_open()
  for _, ns in ipairs(thumbnail_layers) do
    for _, l in ipairs(hl.get_layers({ namespace = ns }) or {}) do
      if l.mapped then return true end
    end
  end
  return false
end

--- Toggles browser opacity when a screenshare session starts or stops, and clears the shared window's effects.
--- Browsers dim when inactive by default; override to full opacity during capture.
local set_screenshare_handler = function()
  hl.on("screenshare.state", function(active, share_type, name)
    if share_type == 1 and thumbnails_open() then return end
    if share_type == 1 then
      tag_shared_window(active, name)
    else
      set_shared_monitor(active, name)
    end
    local opacity = active and "1.0 1.0 override" or BROWSER_OPACITY
    for _, browser in ipairs(browser_rules) do
      hl.window_rule({ name = browser.name, match = { class = browser.class }, opacity = opacity })
    end
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

--- Forces every window opaque and undimmed for the screenshot selector and zoom, skipping the fade so captures never see it mid-way.
--- @param on boolean
function Rules.set_capture_opaque(on)
  hl.animation({ leaf = "fadeSwitch", enabled = not on, speed = FADE_SPEED, bezier = "smooth" })
  local r = Rules.window_rules["capture-opaque"]
  if r then r:set_enabled(on) end
  if on and Rules.saved_dim == nil then
    Rules.saved_dim = hl.get_config("decoration.dim_inactive")
    hl.config({ decoration = { dim_inactive = false } })
  elseif not on and Rules.saved_dim ~= nil then
    hl.config({ decoration = { dim_inactive = Rules.saved_dim } })
    Rules.saved_dim = nil
  end

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

-- Global functions which are accessible externally via `hyprctl dispatch "WindowRules"`
_G.WindowRules = {
  capture_opaque = function(on) return Rules.set_capture_opaque(on) end,
}

local function init()
  set_animations()
  Rules.layer_rules = set_layer_rules()
  set_workspace_rules()
  Rules.window_rules = set_window_rules()
  set_screenshare_handler()
end

init()

return Rules
