local Bind = require("lib.key.bind") ---@class BindLib
local Config = require("config") ---@class Config
local Menu = require("lib.actions.menu") ---@class Menu

local TERM = Config.app.term
local FILES = Config.app.gui_file_manager
local TUI_FILES = Config.app.tui_file_manager

local edit_in_vim = function() require("hyprvim.vim.commands.editor").open({ insert_mode = true }) end
-- stylua: ignore start

-- Leader Commands
Bind.leader_cmd("RETURN",           TERM,                         "Terminal")
Bind.leader_fn("SHIFT + RETURN",    Menu.run(),                   "Run Script")
Bind.leader_fn("CTRL + RETURN",     Menu.ssh(),                   "SSH Select")
Bind.leader_cmd("E",                FILES,                        "File Manager")
Bind.leader_cmd("SHIFT + E",        TERM .. " -e " .. TUI_FILES,  "TUI File Manager")
Bind.leader_fn("O",                 Menu.drun(),                  "Open Application")
Bind.leader_fn("N",                 edit_in_vim,                  "Edit Selection in Vim")
Bind.leader_cmd("Y",                TERM .. " -e yazi",           "Yazi")

-- Commands
Bind.cmd("CTRL + SHIFT + ESCAPE", TERM .. " -e btop", "Task Manager")
