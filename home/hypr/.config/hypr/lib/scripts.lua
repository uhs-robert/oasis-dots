-- home/hypr/.config/hypr/lib/scripts.lua

local HYPR = "~/.config/hypr/scripts/"
local WAYBAR = "~/.config/waybar/scripts/"
local MONITOR = "~/.config/hypr/monitors/scripts/"

--- @class Scripts
--- @field screenshot string
--- @field voxtype string
--- @field focus_media_player string
--- @field nmtui string
--- @field hyprlock string
--- @field rofi_tmux string
--- @field window_selector string
--- @field toggle_monitor_layout string
--- @field confirm_action string
--- @field toggle_mpris_mode string
local Scripts = {
  -- stylua: ignore start
  screenshot            = HYPR    .. "screenshot.sh",
  voxtype               = HYPR    .. "voxtype-with-media-pause.sh",
  focus_media_player    = HYPR    .. "focus-media-player.sh",
  nmtui                 = HYPR    .. "nmtui.sh",
  hyprlock              = HYPR    .. "hyprlock-screenshot.lua",
  rofi_tmux             = HYPR    .. "rofi-tmux.sh",
  window_selector       = HYPR    .. "rofi-hyprwindow.sh",
  toggle_monitor_layout = MONITOR .. "toggle-monitor-layout.sh",
  confirm_action        = WAYBAR  .. "confirm-action.sh",
  toggle_mpris_mode     = WAYBAR  .. "toggle_mpris_mode.rb",
}

return Scripts
