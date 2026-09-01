--- App launcher actions for the Applications submap.
--- All actions dispatch a command or focus/launch a window.

local Config = require("config") ---@class Config
local Cmd = require("lib.actions.cmd") ---@class Cmd
local Window = require("lib.window") ---@class Window

local TERM = Config.app.term
local TERM_CMD = Config.app.term_cmd

--- @class Apps
local Apps = {}

-- stylua: ignore
Apps.map = {
  betterbird  = { program = "betterbird",  class = "eu.betterbird.Betterbird",      cmd = "betterbird" },
  cliamp      = { program = "cliamp",      title = "cliamp",                        cmd = TERM_CMD .. " -e cliamp" },
  thunar      = { program = "thunar",      class = "thunar" },
  firefox     = { program = "firefox",     class = "firefox" },
  hyprconfig  = { program = TERM,          class = "hyprconfig",                    cmd = TERM_CMD .. " --class hyprconfig -e yazi ~/.config/hypr" },
  protonplus  = { program = "protonplus",  class = "protonplus",                    cmd = "protonplus" },
  qutebrowser = { program = "qutebrowser", class = "org.qutebrowser.qutebrowser" },
  slack       = { program = "slack",       class = "slack" },
  steam       = { program = "steam",       class = "steam",                         cmd = "steam"},
  terminal    = { program = TERM,          exclude_title = "Tmux" },
  tmux_ai     = { program = TERM,          title = "Tmux AI",                       cmd = TERM_CMD .. " -e tmuxifier load-session ai" },
  tmux_config = { program = TERM,          title = "Tmux Config",                   cmd = TERM_CMD .. " -e tmuxifier load-session config" },
  tmux_client  = { program = TERM,          title = "Tmux Client App",       cmd = TERM_CMD .. " -e tmuxifier load-session client-dev" },
  tmux_uphill = { program = TERM,          title = "Tmux UpHill",                   cmd = TERM_CMD .. " -e tmuxifier load-session uphill" },
  yazi        = { program = TERM,          class = "yazi",                          cmd = TERM_CMD .. " --class yazi -e yazi" },
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
