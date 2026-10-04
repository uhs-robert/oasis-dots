std = "lua54"
read_globals = { "hl" }
max_line_length = false
unused_args = false
ignore = { "211/[A-Z].*" }

files["system/etc/greetd/hyprland.lua"] = {
  globals = { "GREETD_DIRECTORY", "ADMIN", "RUNTIME_DIR", "TERMINAL", "FULLSCREEN_TERMINAL", "PRIMARY" },
}

exclude_files = { "home/hypr/.config/hypr/lua/plugins/hyprvim/**" }
