local Config = require("config")
local TERM = Config.app.term

-- stylua: ignore
--- Runs all autostart commands on Hyprland session start.
--- Called via `hl.on("hyprland.start", ...)` from config/init.lua.
--- @return nil
local function run()
  os.execute(
    "dbus-update-activation-environment --systemd WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_SESSION_DESKTOP DESKTOP_SESSION GTK_THEME PATH"
  )
  -- The listener outlives a crashed Hyprland (graphical-session.target stays up), keeping the dead instance's signature.
  os.execute("systemctl --user try-restart voxcmd-wake.service")
  os.execute("systemctl --user start hyprland-session.target")
  os.execute("systemctl --user start gnome-keyring-daemon.socket")
  os.execute("gnome-keyring-daemon --start --components=secrets,ssh")
  os.execute("dbus-update-activation-environment --systemd GNOME_KEYRING_CONTROL SSH_AUTH_SOCK")
  -- A tmux server outlives logout, so its environment keeps the last session's values. Never starts a server.
  -- Hyprland's own value wins; the systemd user environment only fills in what Hyprland lacks (SSH_AUTH_SOCK, set just above).
  -- Session-level copies (tmux's update-environment on attach) beat the global value in new panes, so drop them in every session.
  os.execute(
    [[tmux has-session 2>/dev/null && for v in HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY DBUS_SESSION_BUS_ADDRESS SSH_AUTH_SOCK; do ]]
      .. [[val=$(printenv "$v" || systemctl --user show-environment | sed -n "s/^$v=//p"); ]]
      .. [[[ -n "$val" ] && tmux set-environment -g "$v" "$val" && ]]
      .. [[for s in $(tmux list-sessions -F '#{session_id}'); do tmux set-environment -u -t "$s" "$v"; done; done]]
  )
  hl.exec_cmd("~/.config/hypr/scripts/power.sh watch")
  -- Guards machines that still have swaync installed: D-Bus activation would otherwise respawn it and steal notifications from qs.
  os.execute("systemctl --user mask --runtime --now swaync.service")
  hl.exec_cmd("qs -n")
  hl.exec_cmd("easyeffects --gapplication-service")
  hl.exec_cmd("udiskie")
  hl.exec_cmd("wl-paste --type text --watch cliphist store") -- Stores text data
  hl.exec_cmd("wl-paste --type image --watch cliphist store") -- Stores image data
  -- hl.exec_cmd("gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark'") -- Icon theme
  -- hl.exec_cmd("gsettings set org.gnome.desktop.interface gtk-theme 'Breeze-Dark'") -- GTK3 apps
  -- hl.exec_cmd("gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'") -- GTK4 apps
  -- hl.exec_cmd("hyprpm reload")                                                            -- Load plugins
  if Config.wallpaper_enabled then
    hl.exec_cmd("lua ~/.config/hypr/extensions/wallpaper/init.lua" .. (Config.wallpaper_location and " --location" or ""))
  end
end

-- footclient needs a server; switching to foot in Settings only reloads the config, so check on reload too.
local function ensure_foot_server()
  if require("config").app.term == "foot" then hl.exec_cmd("pgrep -f '^foot --server' >/dev/null || foot --server") end
end
hl.on("config.reloaded", ensure_foot_server)

return function()
  ensure_foot_server()
  run()
end
