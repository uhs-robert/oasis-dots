--- Leader submap
--- Entry point to every other submap; direct binds mirror their global leader key

local Config = require("config") --- @class Config
local Cmd = require("lib.actions.cmd") --- @class Cmd
local Menu = require("lib.actions.menu") --- @class Menu
local Scripts = require("lib.scripts") --- @class Scripts
local Submap = require("lib.key.submap") --- @class Submap
local Window = require("lib.actions.window") --- @class WindowActions
local Workspace = require("lib.actions.workspace") --- @class WorkspaceActions
local Launcher = require("extensions.auto_launcher.launcher") ---@class Launcher

local KEEP = { keep = true }

local edit_in_vim = function() require("lua.plugins.hyprvim").editor.open({ insert_mode = true }) end

Submap.define({
  name = "Leader",
  desc = "+Leader",
  enter = Config.leader .. " + SPACE",

  escape = "reset",
  catchall = "reset",

  binds = function()
    local rows = {
      -- stylua: ignore start
      -- Pickers
      { "SPACE",         Menu.zoxide(),                                   "Directory" },
      { "SHIFT + SPACE", Menu.zoxide("claude"),                           "Claude in Directory" },
      { "SLASH",         Cmd.run(Scripts.keybind_help),                   "Keybind Help" },
      { "O",             Menu.drun(),                                     "Open Application" },
      { "SHIFT +O",      Launcher.show_picker,                            "Session Launcher" },
      { "T",             Menu.hyprwindow(),                               "Find Window" },
      { "V",             Menu.clipboard(),                                "Clipboard" },
      { "P",             Menu.bitwarden(),                                "Passwords" },
      { "SHIFT + P",     Menu.tmux(),                                     "Project" },
      { "E",             Menu.emoji(),                                    "Emoji" },
      { "SHIFT + E",     Menu.emoji("nerd_font"),                         "Nerd Font" },
      { "CTRL + E",      Menu.emoji("gitmoji"),                           "Gitmoji" },
      { "ALT + E",       Menu.emoji("fontawesome"),                       "Font Awesome" },
      { "S",             Menu.ssh(),                                      "Open SSH" },

      -- Windows
      { "TAB",           Window.focus_last(),                                     "Last Window" },

      -- Commands
      { "RETURN",        Cmd.open_term(),                                 "Terminal" },
      { "SHIFT + RETURN",Cmd.bottom_terminal(),                           "Bottom Terminal" },
      { "N",             edit_in_vim,                                     "Edit Selection in Vim" },
      { "PERIOD",        Cmd.run(Scripts.voxtype),                        "Speech to Text" },
      { "Y",             Cmd.term("yazi"),                                "Yazi" },

      -- Submaps
      { "A",             Submap.switch("Applications"),                   "+Applications",  KEEP },
      { "G",             Submap.switch("Go"),                             "+Go",            KEEP },
      { "SHIFT + G",     Submap.switch("Groups"),                         "+Groups",        KEEP },
      { "W",             Submap.switch("Windows"),                        "+Windows",       KEEP },
      { "M",             Submap.switch("Move"),                           "+Move",          KEEP },
      { "R",             Submap.switch("Resize"),                         "+Resize",        KEEP },
      { "Z",             Submap.switch("Zoom"),                           "+Zoom",          KEEP },
      { "C",             Submap.switch("Cursor"),                         "+Cursor",        KEEP },
      { "D",             Submap.switch("Delete"),                         "+Delete",        KEEP },
      { "I",             Submap.switch("Screenshot"),                     "+Screenshot",    KEEP },
      { "SHIFT + N",     Submap.switch("Notifications"),                  "+Notifications", KEEP },
      { "Q",             Submap.switch("System"),                         "+System",        KEEP },
      { "APOSTROPHE",    Submap.switch("Marks"),                          "+Marks",         KEEP },
      -- stylua: ignore end
    }

    return rows
  end,
}).setup()
