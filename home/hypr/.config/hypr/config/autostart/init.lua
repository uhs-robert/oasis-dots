-- home/hypr/.config/hypr/config/system/autostart.lua

local Config = require("config")
local TERM = Config.app.term

-- stylua: ignore
--- Runs all autostart commands on Hyprland session start.
--- Called via `hl.on("hyprland.start", ...)` from config/init.lua.
--- @return nil
local function run()
  os.execute(
    "dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_SESSION_DESKTOP DESKTOP_SESSION GTK_THEME PATH"
  )
  os.execute("systemctl --user start hyprland-session.target")
  os.execute("systemctl --user start gnome-keyring-daemon.socket")
  os.execute("gnome-keyring-daemon --start --components=secrets,ssh")
  os.execute("dbus-update-activation-environment --systemd GNOME_KEYRING_CONTROL SSH_AUTH_SOCK")
  if (TERM == 'foot') then hl.exec_cmd('foot --server') end
  hl.exec_cmd("swaync")
  hl.exec_cmd("hypridle")
  hl.exec_cmd("waybar")
  hl.exec_cmd("easyeffects --gapplication-service")
  hl.exec_cmd("udiskie")
  hl.exec_cmd("wl-paste --type text --watch cliphist store") -- Stores text data
  hl.exec_cmd("wl-paste --type image --watch cliphist store") -- Stores image data
  -- hl.exec_cmd("gsettings set org.gnome.desktop.interface gtk-theme 'Breeze-Dark'") -- GTK3 apps
  -- hl.exec_cmd("gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'") -- GTK4 apps
  -- hl.exec_cmd("hyprpm reload")                                                            -- Load plugins
  hl.exec_cmd("lua ~/.config/hypr/extensions/wallpaper/init.lua")
  hl.exec_cmd("voxtype setup systemd")
end

return run
