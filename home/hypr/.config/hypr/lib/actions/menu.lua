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
--- @field args? string Extra arguments appended to the menu invocation.

--- Return the shell command that opens the menu in the given show mode.
--- @param mode string
--- @param opts? Menu.ShowOpts
--- @return string
local function show_cmd(mode, opts)
  opts = opts or {}
  local theme_arg = opts.theme and (" -theme " .. THEME_DIR .. opts.theme) or ""
  return MENU .. " -i -show " .. mode .. theme_arg .. (opts.args and (" " .. opts.args) or "")
end

--- Return an action that opens the menu in the given show mode.
--- @param mode string The mode for the menu
--- @param opts? Menu.ShowOpts
--- @return fun()
Menu.show = function(mode, opts)
  opts = opts or {}
  local rule = opts.layer_rule
  local cmd = show_cmd(mode, opts)
  return function()
    if rule then
      hl.dispatch(Rules.exec_with_layer_rule(rule, cmd))
    else
      hl.dispatch(hl.dsp.exec_cmd(cmd))
    end
  end
end

--- Return an action that opens Quickshell's `provider` picker under the Quickshell shell, else runs `fallback`.
--- @param provider string
--- @param fallback string Shell command, also run when the bar is not running or lacks the picker.
--- @return fun()
function Menu.picker(provider, fallback)
  if Config.shell ~= "quickshell" then return Cmd.run(fallback) end
  return Cmd.run(Scripts.qs_picker .. " " .. provider .. " '" .. fallback:gsub("'", "'\\''") .. "'")
end

-- Basic Action
Menu.drun = function() return Menu.picker("apps", show_cmd("drun")) end
Menu.run = function() return Menu.show("run") end
Menu.ssh = function() return Menu.show("ssh") end
Menu.window = function() return Menu.show("window") end
Menu.hyprwindow = function() return Menu.show("hyprwindow") end

--- Return an action that picks a $PATH executable and runs it in a terminal.
--- @return fun()
function Menu.cli()
  local inner = [==[zsh -c \"export NO_FASTFETCH=1; exec zsh -i -c '{cmd}; exec zsh -i'\"]==]
  return Menu.show("run", { args = '-run-command "' .. TERM_CMD .. " -e " .. inner .. '"' })
end

--- Return an action that opens the tmux session picker.
--- @return fun()
function Menu.tmux() return Cmd.run(Scripts.rofi_tmux) end

--- Return an action that opens the keeptabs agent session picker.
--- @return fun()
function Menu.agents() return Cmd.run("~/.local/bin/keeptabs-pick") end

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

--- Return an action that opens a zoxide directory in the file manager, or in `app` when given.
--- @param app? string
--- @return fun()
function Menu.zoxide(app)
  local picker = DMENU_CMD .. " -theme-str 'listview { columns: 1; }' -p 'Directory'"
  local shell = [[zsh -i -c 'cd "{}" && ]] .. (app or "y") .. [[; exec zsh -i']]
  local class = app and "" or (" --class " .. FILE_MANAGER)
  local open = TERM_CMD .. class .. " -e " .. shell
  return Cmd.run("zoxide query -l | " .. picker .. " | xargs -r -I{} " .. open)
end

--- Return an action that picks a character and types it into the focused window.
--- @param files? string|string[] rofimoji file set(s), e.g. "nerd_font" (default: emoji)
--- @return fun()
function Menu.emoji(files)
  local list = type(files) == "table" and files or { files }
  local files_arg = files and (" --files " .. table.concat(list, " ")) or ""
  return Cmd.run("rofimoji --action type" .. files_arg .. " --selector-args '-name rofiDmenu'")
end

--- Return an action that picks a Bitwarden entry (see ~/.config/rofi-rbw.rc).
--- @return fun()
function Menu.bitwarden() return Cmd.run("rofi-rbw") end

return Menu
