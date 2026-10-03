--- Leader submap
--- Entry point to every other submap; direct binds mirror their global leader key

local Config = require("config") --- @class Config
local Cmd = require("lib.actions.cmd") --- @class Cmd
local Menu = require("lib.actions.menu") --- @class Menu
local Popups = require("lib.actions.popups") --- @class Popups
local Scripts = require("lib.scripts") --- @class Scripts
local Submap = require("lib.key.submap") --- @class Submap
local Window = require("lib.actions.window") --- @class WindowActions
local Workspace = require("lib.actions.workspace") --- @class WorkspaceActions
local Launcher = require("extensions.auto_launcher.launcher") ---@class Launcher

local KEEP = { keep = true }

Submap.define({
  name = "Leader",
  desc = "+Leader",
  enter = Config.leader .. " + SPACE",

  escape = "reset",
  catchall = "reset",

  binds = function()
    local binds = {
      -- stylua: ignore start
      -- Pickers
      { "SLASH",         Menu.zoxide(),                                   "Directory" },
      { "O",             Menu.drun(),                                     "Open Application" },
      { "SHIFT + O",     Launcher.show_picker,                            "Session Launcher" },
      { "CTRL + V",      Menu.clipboard(),                                "Clipboard" },
      { "TAB",           Menu.overview(),                                 "Workspace Overview" },
      { "SHIFT + TAB",   Menu.tmux_overview(),                            "Tmux Overview" },
      { "E",             Menu.emoji(),                                    "Emoji" },

      -- Commands
      { "PERIOD",        Cmd.run(Scripts.voxtype),                        "Speech to Text" },

      -- Submaps
      { "G",             Submap.switch("Groups"),                         "+Groups",        KEEP },
      -- stylua: ignore end
    }

    table.insert(binds, { "SPACE", Popups.open("start"), "Start Menu" })
    local settings = { "S", Popups.open("settings"), "Settings" }
    for _, row in ipairs(Popups.binds({ S = settings })) do
      table.insert(binds, row)
    end
    return binds
  end,
}).setup()
