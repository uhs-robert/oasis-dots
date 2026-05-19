--- App launcher actions for the Applications submap.
--- All actions dispatch a command or focus/launch a window.

local Config = require("config") ---@class Config
local Cmd = require("lib.actions.cmd") ---@class Cmd
local Window = require("lib.window") ---@class Window

local TERM = Config.app.term

--- @class Apps
local Apps = {}

-- stylua: ignore
Apps.map = {
  betterbird  = { program = "betterbird",  class = "eu.betterbird.Betterbird",      cmd = "flatpak run eu.betterbird.Betterbird" },
  cliamp      = { program = "cliamp",      title = "cliamp",                        cmd = TERM .. " -e cliamp" },
  dolphin     = { program = "dolphin",     class = "org.kde.dolphin" },
  firefox     = { program = "firefox",     class = "org.mozilla.firefox" },
  hyprconfig  = { program = TERM,          class = "hyprconfig",                    cmd = TERM .. " --class hyprconfig -e yazi ~/.config/hypr" },
  protonplus  = { program = "protonplus",  class = "com.vysp3r.ProtonPlus",         cmd = "flatpak run com.vysp3r.ProtonPlus" },
  qutebrowser = { program = "qutebrowser", class = "org.qutebrowser.qutebrowser" },
  slack       = { program = "slack",       class = "Slack" },
  steam       = { program = "steam",       class = "Steam",                         cmd = "steam"},
  terminal    = { program = TERM,          exclude_title = "Tmux" },
  tmux_config = { program = TERM,          title = "Tmux Config",                   cmd = TERM .. " -e tmuxifier load-session config" },
  tmux_client  = { program = TERM,          title = "Tmux Client App",       cmd = TERM .. " -e tmuxifier load-session client-dev" },
  tmux_uphill = { program = TERM,          title = "Tmux UpHill",                   cmd = TERM .. " -e tmuxifier load-session uphill" },
  yazi        = { program = TERM,          class = "yazi",                          cmd = TERM .. " --class yazi -e yazi" },
}

--- Return an action that runs a shell command.
--- @param app_command string
--- @return fun()
Apps.open = function(app_command) return Cmd.run(app_command) end

--- Return an action that focuses an existing window or launches the app.
--- @param opts { program: string, class?: string, title?: string, exclude_title?: string, cmd?: string }
--- @return fun()
Apps.focus_or_launch = function(opts)
  return function() Window.focus_or_launch(opts) end
end

return Apps
