-- Actions for the System submap: reloads, restarts, the update terminal, theme and wallpaper. No default keys: the System
-- rows (and the Bar's Updates row) bind them. Logout, lock, reboot and power off are not here; they stay plain rows until
-- they are power actions of their own.
local Act = require("lib.act") ---@class ActionLib
local Scripts = require("lib.scripts") ---@class Scripts
local Cmd = Act.Cmd

--- A function `run` for a shell command line (pipes, `||`, `~` mid-word) that Act.Cmd would quote. Config-dependent
--- commands pass a function so Config is read on each press.
--- @param command string|fun(): string
--- @return fun()
local function shell(command)
  return function()
    local line = type(command) == "function" and command() or command
    require("lib.actions.cmd").run(line)()
  end
end

Act.define("system.edit_keymaps", {
  label = "Edit Keymaps",
  intent = "Open the Hyprland keymaps folder in the terminal file manager.",
  run = function()
    local files = require("config").app.tui_file_manager
    require("lib.actions.cmd").term(files .. " ~/.config/hypr/keymaps/")()
  end,
})

Act.define("system.restart_bar", {
  label = "Restart Bar",
  intent = "Stop the Quickshell bar and start it again.",
  run = Cmd("~/.config/hypr/scripts/restart-bar.sh"),
})

Act.define("system.display_manager", {
  label = "Display Manager",
  intent = "Open the monitor layout tool.",
  run = shell(function() return require("config").app.display_manager end),
})

Act.define("system.reload_hyprland", {
  label = "Reload Hyprland",
  intent = "Reload the Hyprland configuration.",
  run = Cmd("hyprctl", "reload"),
})

Act.define("system.reload_plugins", {
  label = "Reload Hyprpm Plugins",
  intent = "Reload the Hyprland plugins installed with hyprpm.",
  run = Cmd("hyprpm", "reload", "-n"),
})

Act.define("system.network", {
  label = "Internet (nmtui)",
  intent = "Open the network manager in a terminal.",
  run = Cmd(Scripts.nmtui),
})

Act.define("system.kill_app", {
  label = "Kill App (Click)",
  intent = "Kill the window you click on next.",
  run = Cmd("hyprctl", "kill"),
})

Act.define("system.toggle_autolock", {
  label = "Toggle Auto-Lock",
  intent = "Turn the automatic screen lock on, or off when it is on.",
  run = Cmd(Scripts.toggle_autolock),
})

Act.define("system.replay_autostart", {
  label = "Replay Autostart",
  intent = "Run the session start-up commands again.",
  run = function() require("config.autostart")() end,
})

Act.define("system.theme_switch", {
  label = "Theme Switch",
  intent = "Open the colour theme picker.",
  run = shell(
    function()
      return Scripts.qs_ipc
        .. " call settings open colors >/dev/null 2>&1 || ~/.config/hypr/theme/switch.lua '"
        .. require("config").app.dmenu_cmd
        .. "'"
    end
  ),
})

Act.define("system.update", {
  label = "Update System",
  intent = "Focus the system update terminal, or start the update.",
  run = Cmd(Scripts.focus_topgrade),
})

Act.define("system.voxtype_settings", {
  label = "Voxtype Settings",
  intent = "Open the voxtype settings in a terminal.",
  run = function() require("lib.actions.cmd").term("voxtype configure")() end,
})

Act.define("system.voxtype_restart", {
  label = "Voxtype Restart",
  intent = "Restart the voxtype service.",
  run = function() require("lib.actions.cmd").term("systemctl --user restart voxtype")() end,
})

Act.define("system.next_wallpaper", {
  label = "Next Wallpaper",
  intent = "Switch to the next wallpaper now.",
  run = shell("lua ~/.config/hypr/extensions/wallpaper/init.lua --once"),
})

Act.define("system.disable_errors", {
  label = "Disabled Hypr Errors",
  intent = "Hide the Hyprland configuration error banner.",
  run = Cmd("hyprctl", "seterror", "disable"),
})
