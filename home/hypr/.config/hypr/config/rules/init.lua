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

--- @param w table
--- @return boolean
local function has_shared_tag(w)
  local tags = type(w.tags) == "table" and table.concat(w.tags, ",") or (w.tags or "")
  return string.find("," .. tags .. ",", ",shared,", 1, true) ~= nil
end

--- Tags the window titled `name` so it shows opaque and undimmed; a window already tagged is left alone.
--- @param name string
local function tag_shared_window(name)
  for _, w in ipairs(hl.get_windows() or {}) do
    if w.title == name then
      if not has_shared_tag(w) then
        hl.dispatch(hl.dsp.window.tag({ window = "address:" .. w.address, tag = "+shared" }))
      end
      return
    end
  end
end

local function untag_shared_windows()
  for _, w in ipairs(hl.get_windows() or {}) do
    if has_shared_tag(w) then hl.dispatch(hl.dsp.window.tag({ window = "address:" .. w.address, tag = "-shared" })) end
  end
end

--- Monitor name -> its opaque rule, for the monitors shared during the live share.
local shared_monitors = {}

--- Shows every window on the monitor opaque and undimmed; one rule per monitor for the whole share.
--- @param name string
local function share_monitor(name)
  if shared_monitors[name] then return end
  shared_monitors[name] = hl.window_rule({
    name = "shared-monitor-" .. name,
    match = { workspace = "m[" .. name .. "]" },
    opacity = "1.0 override 1.0 override",
    no_dim = true,
  })
end

local function unshare_monitors()
  for _, rule in pairs(shared_monitors) do
    rule:set_enabled(false)
  end
  shared_monitors = {}
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

--- Browsers dim when inactive by default; override to full opacity during a share.
--- @param opacity string
local function set_browser_opacity(opacity)
  for _, browser in ipairs(browser_rules) do
    hl.window_rule({ name = browser.name, match = { class = browser.class }, opacity = opacity })
  end
end

-- Whether a portal share runs, as reported by Quickshell watching xdph's PipeWire node. The
-- screenshare.state event can't say: it goes false between frames of a static screen (flapping every
-- second) and fires for Quickshell's own thumbnail captures. A config reload resets this to false,
-- and Quickshell resends the live state on reload.
local portal_share_live = false

--- "<share_type>:<name>" -> target Hyprland currently copies frames for. The share's first frame can
--- arrive before Quickshell reports it live, and a busy screen never sends another, so going live
--- applies whatever is already sharing.
local sharing_targets = {}

--- screenshare.state share_type for a single window; monitor and region shares carry a monitor name.
local WINDOW_SHARE = 1

--- @param share_type integer
--- @param name string
local function apply_share_target(share_type, name)
  if share_type ~= WINDOW_SHARE then
    share_monitor(name)
  elseif not thumbnails_open() then
    tag_shared_window(name)
  end
end

--- Applies the rules for a share target once live, naming it as the events arrive.
--- Ignores `active = false` while live: that is a gap between frames, not the end of the share.
local set_screenshare_handler = function()
  hl.on("screenshare.state", function(active, share_type, name)
    sharing_targets[share_type .. ":" .. name] = active and { share_type = share_type, name = name } or nil
    if portal_share_live and active then apply_share_target(share_type, name) end
  end)
end

--- Starts or ends the share's effects; repeating the current state does nothing, so resends cause no fade.
--- @param on boolean
local function set_live(on)
  if on == portal_share_live then return end
  portal_share_live = on
  if on then
    set_browser_opacity("1.0 1.0 override")
    for _, target in pairs(sharing_targets) do
      apply_share_target(target.share_type, target.name)
    end
  else
    -- Drops targets whose stop never arrived, such as a window renamed mid-share.
    sharing_targets = {}
    unshare_monitors()
    untag_shared_windows()
    set_browser_opacity(BROWSER_OPACITY)
  end
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

-- Global functions which are accessible externally via `hyprctl dispatch "ScreenShare"`
_G.ScreenShare = {
  set_live = function(on)
    set_live(on)

    return hl.dsp.no_op()
  end,
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
