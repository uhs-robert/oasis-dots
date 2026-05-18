local Bind = require("lib.key.bind")
local Config = require("config")

local TERM = Config.app.term
local FILES = Config.app.gui_file_manager
local TUI_FILES = Config.app.tui_file_manager
local MENU = Config.app.menu

local edit_in_vim = function() require("hyprvim.vim.commands.editor").open({ insert_mode = true }) end
-- stylua: ignore start


-- Leader Commands
Bind.leader_cmd("RETURN",           TERM,                           { desc = "Terminal" })
Bind.leader_cmd("SHIFT + RETURN",   MENU .. " -i -show run",        { desc = "Run Script" })
Bind.leader_cmd("CTRL + RETURN",    MENU .. " -i -show ssh",        { desc = "SSH Select" })
Bind.leader_cmd("E",                FILES,                          { desc = "File Manager" })
Bind.leader_cmd("SHIFT + E",        TERM .. " -e " .. TUI_FILES,    { desc = "TUI File Manager" })
Bind.leader_cmd("O",                MENU .. " -i -show drun",       { desc = "Open Application" })
Bind.leader_fn("N",                 edit_in_vim,                    { desc = "Edit Selection in Vim" })
Bind.leader_cmd("Y",                TERM .. " -e yazi",             { desc = "Yazi" })

-- Commands
Bind.cmd("CTRL + SHIFT + ESCAPE", TERM .. " -e btop", { desc = "Task Manager" })
