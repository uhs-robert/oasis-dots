std = "lua54"
read_globals = { "hl" }
max_line_length = false
unused_args = false
ignore = { "211/[A-Z].*" }

files["system/etc/greetd/hyprland.lua"] = {
  globals = { "GREETD_DIRECTORY", "ADMIN", "RUNTIME_DIR", "TERMINAL", "FULLSCREEN_TERMINAL", "PRIMARY" },
}

files["home/hypr/.config/hypr/extensions/wallpaper/lib/rotate.lua"] = {
  ignore = { "311/cleanup_lock" },
}
