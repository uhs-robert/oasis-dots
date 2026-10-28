local HYPR = "~/.config/hypr/scripts/"
local BIN = "~/.local/bin/"

--- @class Scripts
local Scripts = {
  -- stylua: ignore start
  screenshot            = HYPR    .. "screenshot.sh",
  voxtype               = HYPR    .. "voxtype-with-media-pause.sh",
  voxcmd_listen         = BIN     .. "voxcmd listen",
  voxcmd_stop           = BIN     .. "voxcmd stop",
  voxcmd_rapid          = BIN     .. "voxcmd session rapid",
  voxcmd_wake           = BIN     .. "voxcmd wake toggle",
  voxcmd_help           = BIN     .. "voxcmd help",
  focus_media_player    = HYPR    .. "focus-media-player.sh",
  focus_toast_popup_or_float = HYPR    .. "focus-toast-popup-or-float.sh",
  focus_topgrade        = HYPR    .. "focus-topgrade.sh",
  qs_ipc                = HYPR    .. "qs-ipc",
  qs_picker             = HYPR    .. "qs-picker",
  toggle_autolock       = HYPR    .. "toggle-autolock.sh",
  toggle_hypr_errors    = HYPR    .. "toggle-hypr-errors.sh",
  power                 = HYPR    .. "power.sh",
  rofi_tmux             = HYPR    .. "rofi-tmux.sh",
  keybind_help          = HYPR    .. "keybind-help.lua",
  kitty_window_cmd      = HYPR    .. "kitty-window-cmd.sh",
}

return Scripts
