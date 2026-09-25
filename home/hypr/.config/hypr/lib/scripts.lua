-- home/hypr/.config/hypr/lib/scripts.lua

local HYPR = "~/.config/hypr/scripts/"
local MONITOR = "~/.config/hypr/monitors/scripts/"

--- @class Scripts
local Scripts = {
  -- stylua: ignore start
  screenshot            = HYPR    .. "screenshot.sh",
  voxtype               = HYPR    .. "voxtype-with-media-pause.sh",
  focus_media_player    = HYPR    .. "focus-media-player.sh",
  focus_toast_or_float  = HYPR    .. "focus-toast-or-float.sh",
  qs_ipc                = HYPR    .. "qs-ipc",
  qs_picker             = HYPR    .. "qs-picker",
  nmtui                 = HYPR    .. "nmtui.sh",
  hyprlock              = HYPR    .. "hyprlock-screenshot.lua",
  rofi_tmux             = HYPR    .. "rofi-tmux.sh",
  window_selector       = HYPR    .. "rofi-hyprwindow.sh",
  keybind_help          = HYPR    .. "keybind-help.lua",
  toggle_monitor_layout = MONITOR .. "toggle-monitor-layout.sh",
}

return Scripts
