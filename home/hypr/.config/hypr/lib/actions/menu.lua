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
local SHELL = (os.getenv("SHELL") or "zsh"):match("[^/]+$")
local IS_ROFI = MENU:match("[^/]+$") == "rofi"
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

--- Return an action that opens Quickshell's `provider` picker, falling back to `fallback` when it is unavailable.
--- @param provider string
--- @param fallback string Shell command, run when the bar is not running or lacks the picker.
--- @param mode? string Passed to the provider on open, e.g. "move".
--- @return fun()
function Menu.picker(provider, fallback, mode)
  local function quote(s) return "'" .. s:gsub("'", "'\\''") .. "'" end
  return Cmd.run(
    Scripts.qs_picker .. " " .. provider .. " " .. quote(fallback) .. (mode and (" " .. quote(mode)) or "")
  )
end

-- Basic Action
Menu.drun = function() return Menu.picker("apps", show_cmd("drun")) end
Menu.run = function() return Menu.show("run") end
Menu.ssh = function() return Menu.show("ssh") end
Menu.window = function() return Menu.show("window") end

--- Return an action that lists the active submap's described binds, falling back to the rofi script.
--- @return fun()
function Menu.keybinds()
  return function() Menu.picker("keybinds", Scripts.keybind_help, hl.get_current_submap())() end
end

--- Return an action that opens the Quickshell workspace overview.
--- @return fun()
function Menu.overview() return Cmd.run(Scripts.qs_ipc .. " call overview open") end

--- Return an action that opens the Quickshell tmux overview.
--- @return fun()
function Menu.tmux_overview() return Cmd.run(Scripts.qs_ipc .. " call tmux-overview open") end

--- Return an action that opens the workspace overview with window search active.
--- @return fun()
function Menu.overview_search() return Cmd.run(Scripts.qs_ipc .. " call overview search") end

--- Return an action that opens the overview carrying the focused window, to drop it on a workspace.
--- @param follow boolean Follow the window to its new workspace.
--- @return fun()
function Menu.overview_move(follow)
  return Cmd.run(Scripts.qs_ipc .. " call overview " .. (follow and "move_follow" or "move_silent"))
end

--- Return an action that picks a $PATH executable and runs it in a terminal.
--- @return fun()
function Menu.cli()
  local inner = "env NO_FASTFETCH=1 " .. SHELL .. " -i -c '{cmd}; exec " .. SHELL .. " -i'"
  return Menu.show("run", { args = '-run-command "' .. TERM_CMD .. " -e " .. inner .. '"' })
end

--- Return an action that opens the tmux session picker.
--- @return fun()
function Menu.tmux() return Cmd.run(Scripts.rofi_tmux) end

--- Return an action that opens the Quickshell keeptabs popup, falling back to the rofi picker.
--- @return fun()
function Menu.agents()
  local open = Scripts.qs_ipc .. " call popup open keeptabs"
  local pick = "~/.local/bin/keeptabs-pick"
  return Cmd.run(
    "sh -c 'out=$(" .. open .. ' 2>&1) && [ -z "$out" ] || { [ -x ' .. pick .. " ] && exec " .. pick .. "; }'"
  )
end

--- Return an action that picks a clipboard history entry and copies it back.
--- @return fun()
function Menu.clipboard()
  local picker = DMENU_CMD .. " -p 'Clipboard'"
  return Menu.picker("clipboard", "cliphist list | " .. picker .. " | cliphist decode | wl-copy")
end

--- Return an action that deletes a single clipboard history entry.
--- @return fun()
function Menu.clipboard_delete()
  local picker = DMENU_CMD .. " -p 'Delete from clipboard'"
  return Menu.picker("clipboard", "cliphist list | " .. picker .. " | cliphist delete", "delete")
end

--- Return an action that opens a zoxide directory in the file manager, or in `app` when given.
--- @param app? string
--- @return fun()
function Menu.zoxide(app)
  local picker = DMENU_CMD .. (IS_ROFI and " -theme-str 'listview { columns: 1; }'" or "") .. " -p 'Directory'"
  local fm = FILE_MANAGER == "yazi" and "if type y >/dev/null 2>&1; then y; else yazi; fi" or FILE_MANAGER
  local shell = SHELL .. ' -i -c \'cd "{}" && ' .. (app or fm) .. "; exec " .. SHELL .. " -i'"
  local class = app and "" or (" --class " .. FILE_MANAGER)
  local open = TERM_CMD .. class .. " -e " .. shell
  local rofi = "zoxide query -l | " .. picker .. " | xargs -r -I{} " .. open
  if app then return Cmd.run(rofi) end
  return Menu.picker("dirs", rofi, FILE_MANAGER)
end

--- Return an action that picks a character and types it into the focused window.
--- @return fun()
function Menu.emoji()
  local args = IS_ROFI and " --selector-args '-name rofiDmenu'" or ""
  return Menu.picker("emoji", "rofimoji --action type" .. args)
end

--- Return an action that picks a Bitwarden entry (see ~/.config/rofi-rbw.rc).
--- @return fun()
function Menu.bitwarden() return Cmd.run("rofi-rbw") end

return Menu
