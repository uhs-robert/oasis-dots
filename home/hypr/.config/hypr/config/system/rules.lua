-- home/hypr/.config/hypr/config/system/rules.lua

--- Registers bezier curves and animation definitions for windows, workspaces, fade, and layers.
local set_animations = function()
  -- https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/
  hl.curve("smooth", { type = "bezier", points = { { 0.22, 1 }, { 0.1, 1.1 } } })
  hl.curve("quick", { type = "bezier", points = { { 0.15, 0.85 }, { 0.25, 1.0 } } })
  hl.curve("overshot", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.08 } } })
  hl.curve("linearish", { type = "bezier", points = { { 0.3, 0.0 }, { 0.7, 1.0 } } })

  -- WINDOWS
  hl.animation({ leaf = "windows", enabled = true, speed = 4, bezier = "smooth", style = "popin 95%" })
  hl.animation({ leaf = "windowsIn", enabled = true, speed = 4, bezier = "smooth", style = "popin 85%" })
  hl.animation({ leaf = "windowsOut", enabled = true, speed = 3, bezier = "quick", style = "popin 90%" })
  hl.animation({ leaf = "windowsMove", enabled = true, speed = 3, bezier = "quick" })

  -- WORKSPACES
  hl.animation({ leaf = "workspaces", enabled = true, speed = 5, bezier = "smooth", style = "slidefade 20%" })
  hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 3, bezier = "smooth", style = "slidefadevert 5%" })

  -- MISC
  hl.animation({ leaf = "fade", enabled = true, speed = 3, bezier = "linearish" })
  hl.animation({ leaf = "layers", enabled = true, speed = 3, bezier = "quick", style = "fade" })
end

--- Applies animation layer rules for shell surfaces (waybar, rofi, notifications, etc.).
local set_layer_rules = function()
  -- https://wiki.hypr.land/Configuring/Basics/Window-Rules/#layer-rules
  hl.layer_rule({ match = { namespace = "waybar" }, animation = "fade" })
  hl.layer_rule({ match = { namespace = "rofi" }, animation = "popin" })
  hl.layer_rule({ match = { namespace = "hyprpaper" }, animation = "fade" })
  hl.layer_rule({ match = { namespace = "selection" }, animation = "fade" })
  hl.layer_rule({ match = { namespace = "notificationsmenu" }, animation = "slide right" })
  hl.layer_rule({ match = { namespace = "dashboardmenu" }, animation = "slide left" })
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
    match = { class = "^(float)$" },
    float = true,
    size = "(monitor_w*0.8) (monitor_h*0.8)",
    dim_around = true,
  })
  hl.window_rule({ name = "fix-dropdown-opacity", match = { float = true }, opacity = "1.0 1.0 override" })

  -- Browsers
  hl.window_rule({ name = "firefox-opacity",     match = { class = "^(org\\.mozilla\\.firefox)$" },          opacity = "1.0 override 0.85 override" })
  hl.window_rule({ name = "qutebrowser-opacity", match = { class = "^(org\\.qutebrowser\\.qutebrowser)$" },  opacity = "1.0 override 0.85 override" })

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
    hl.window_rule({ name = "firefox-opacity",     match = { class = "^(org\\.mozilla\\.firefox)$" },         opacity = opacity })
    hl.window_rule({ name = "qutebrowser-opacity", match = { class = "^(org\\.qutebrowser\\.qutebrowser)$" }, opacity = opacity })
  end)
end

local function init()
  set_animations()
  set_layer_rules()
  set_workspace_rules()
  set_window_rules()
  set_screenshare_handler()
end

init()
