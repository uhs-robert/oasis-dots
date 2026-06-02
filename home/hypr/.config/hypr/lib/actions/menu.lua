--- Menu launcher actions.
--- All actions open the configured menu app and return fun().

local Config = require("config") ---@class Config
local Cmd = require("lib.actions.cmd") ---@class Cmd
local Rules = require("config.rules") ---@class Rules
local Scripts = require("lib.scripts") ---@class Scripts

local MENU = Config.app.menu
local THEME_DIR = "~/.config/" .. MENU .. "/themes/"

--- @class Menu
local Menu = {}

--- @class Menu.ShowOpts
--- @field theme? string Filename (without path) of the rofi theme in the themes dir.
--- @field layer_rule? string Layer rule name to enable for the duration.

--- Return an action that opens the menu in the given show mode.
--- @param mode string The mode for the menu
--- @param opts? Menu.ShowOpts
--- @return fun()
Menu.show = function(mode, opts)
  opts = opts or {}
  local theme, rule = opts.theme, opts.layer_rule
  local theme_arg = theme and (" -theme " .. THEME_DIR .. theme) or ""
  local cmd = MENU .. " -i -show " .. mode .. theme_arg
  return function()
    if rule then
      hl.dispatch(Rules.exec_with_layer_rule(rule, cmd))
    else
      hl.dispatch(hl.dsp.exec_cmd(cmd))
    end
  end
end

-- Basic Action
Menu.drun = function() return Menu.show("drun") end
Menu.run = function() return Menu.show("run") end
Menu.ssh = function() return Menu.show("ssh") end
Menu.window = function() return Menu.show("window") end
Menu.hyprwindow = function() return Menu.show("hyprwindow") end

--- Return an action that opens the tmux session picker.
--- @return fun()
function Menu.tmux() return Cmd.run(Scripts.rofi_tmux) end

return Menu
