--- Menu launcher actions.
--- All actions open the configured menu app and return fun().

local Config = require("config") ---@class Config
local Cmd = require("lib.actions.cmd") ---@class Cmd
local Rules = require("config.rules") ---@class Rules
local Scripts = require("lib.scripts") ---@class Scripts

local MENU = Config.app.menu
local DMENU_CMD = Config.app.dmenu_cmd
local TERM_CMD = Config.app.term_cmd
local FILE_MANAGER = Config.app.tui_file_manager
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

--- Return an action that picks a clipboard history entry and copies it back.
--- @return fun()
function Menu.clipboard()
  local picker = DMENU_CMD .. " -p 'Clipboard'"
  return Cmd.run("cliphist list | " .. picker .. " | cliphist decode | wl-copy")
end

--- Return an action that deletes a single clipboard history entry.
--- @return fun()
function Menu.clipboard_delete()
  local picker = DMENU_CMD .. " -p 'Delete from clipboard'"
  return Cmd.run("cliphist list | " .. picker .. " | cliphist delete")
end

--- Return an action that jumps to a zoxide directory in the file manager.
--- @return fun()
function Menu.zoxide()
  local picker = DMENU_CMD .. " -theme-str 'listview { columns: 1; }' -p 'Directory'"
  local shell = [[zsh -i -c 'cd "{}" && y; exec zsh -i']]
  local open = TERM_CMD .. " --class " .. FILE_MANAGER .. " -e " .. shell
  return Cmd.run("zoxide query -l | " .. picker .. " | xargs -r -I{} " .. open)
end

--- Return an action that picks an emoji and types it into the focused window.
--- @return fun()
function Menu.emoji() return Cmd.run("rofimoji --action type --selector-args '-name rofiDmenu'") end

--- Return an action that picks a Bitwarden entry (see ~/.config/rofi-rbw.rc).
--- @return fun()
function Menu.bitwarden() return Cmd.run("rofi-rbw") end

return Menu
