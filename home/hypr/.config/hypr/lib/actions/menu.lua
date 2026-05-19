--- Menu launcher actions.
--- All actions open the configured menu app and return fun().

local Config = require("config") ---@class Config
local Cmd = require("lib.actions.cmd") ---@class Cmd
local Scripts = require("lib.scripts") ---@class Scripts

local MENU = Config.app.menu

--- @class Menu
local Menu = {}

--- Return an action that opens the menu in the given show mode.
--- @param mode string
--- @return fun()
Menu.show = function(mode) return Cmd.run(MENU .. " -i -show " .. mode) end

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
