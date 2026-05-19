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
function Menu.show(mode) return Cmd.run(MENU .. " -i -show " .. mode) end

-- stylua: ignore start
function Menu.drun()       return Menu.show("drun") end
function Menu.run()        return Menu.show("run") end
function Menu.ssh()        return Menu.show("ssh") end
function Menu.window()     return Menu.show("window") end
function Menu.hyprwindow() return Menu.show("hyprwindow") end
-- stylua: ignore end

--- Return an action that opens the tmux session picker.
--- @return fun()
function Menu.tmux() return Cmd.run(Scripts.rofi_tmux) end

return Menu
