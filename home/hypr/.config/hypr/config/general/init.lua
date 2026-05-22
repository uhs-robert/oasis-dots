-- home/hypr/.config/hypr/config/system/general.lua
--- Applies global Hyprland options: layout, decoration, input, cursor, animations, and misc.

local Config = require("config") ---@class Config

local IS_LAPTOP = Config.is_laptop
local ENABLE_NVIDIA = Config.nvidia.enable

-- https://wiki.hypr.land/Configuring/Basics/Variables/
hl.config({
  general = {
    gaps_in = 4,
    gaps_out = 6,
    border_size = 2,
    resize_on_border = true,
    allow_tearing = false,
    layout = "dwindle",
  },

  decoration = {
    rounding = 0,
    active_opacity = 1,
    inactive_opacity = 0.5,
    dim_inactive = true,
    dim_strength = 0.2,
    shadow = {
      enabled = not IS_LAPTOP,
      range = 4,
      render_power = 3,
    },
    blur = {
      enabled = not IS_LAPTOP,
      size = 3,
      passes = 1,
      vibrancy = 0.1696,
    },
  },

  input = {
    numlock_by_default = false,
    kb_layout = "us",
    follow_mouse = 1,
    mouse_refocus = false,
    sensitivity = 0,
    touchpad = {
      natural_scroll = false,
    },
  },

  cursor = {
    no_hardware_cursors = ENABLE_NVIDIA and 1 or 2,
    inactive_timeout = 2,
    hide_on_key_press = true,
    enable_hyprcursor = true,
  },

  binds = {
    allow_workspace_cycles = true,
  },

  ecosystem = {
    no_donation_nag = true,
  },

  quirks = {
    prefer_hdr = false,
  },

  misc = {
    force_default_wallpaper = 0,
    disable_hyprland_logo = true,
    disable_splash_rendering = true,
  },

  -- https://wiki.hypr.land/Configuring/Layouts/Dwindle-Layout/
  dwindle = {
    force_split = 2,
    preserve_split = true,
    smart_split = false,
  },

  -- https://wiki.hypr.land/Configuring/Layouts/Master-Layout/
  master = {
    new_status = "master",
  },
})
