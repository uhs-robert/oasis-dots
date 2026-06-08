local Bind = require("lib.key.bind") ---@class BindLib
local Config = require("config") ---@class Config
local Cmd = require("lib.actions.cmd") ---@class Cmd
local Menu = require("lib.actions.menu") ---@class Menu
local Cursor = require("lib.actions.cursor") ---@class CursorActions

local FILES = Config.app.gui_file_manager
local TUI_FILES = Config.app.tui_file_manager

local edit_in_vim = function() require("lua.plugins.hyprvim").editor.open({ insert_mode = true }) end
-- stylua: ignore start

-- Leader Commands
Bind.leader_fn("RETURN",         Cmd.open_term(),     "Terminal")
Bind.leader_fn("SHIFT + RETURN", Menu.run(),          "Run Script")
Bind.leader_fn("CTRL + RETURN",  Menu.ssh(),          "SSH Select")
Bind.leader_cmd("E",             FILES,               "File Manager")
Bind.leader_fn("SHIFT + E",      Cmd.term(TUI_FILES), "TUI File Manager")
Bind.leader_fn("O",              Menu.drun(),         "Open Application")
Bind.leader_fn("N",              edit_in_vim,         "Edit Selection in Vim")
Bind.leader_fn("Y",              Cmd.term("yazi"),    "Yazi")
Bind.leader_fn("SEMICOLON",      Cursor.kbptr("floating_click", { exit = true }), "Floating Click (Exit)")

-- Commands
Bind.fn("CTRL + SHIFT + ESCAPE", Cmd.term("btop"),    "Task Manager")
