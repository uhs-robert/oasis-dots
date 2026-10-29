--- Leader submap
--- Entry point to every other submap; direct binds mirror their global leader key

local BarRows = require("keymaps.submaps.bar.rows") --- @class BarRows
local Config = require("config") --- @class Config
local Cmd = require("lib.actions.cmd") --- @class Cmd
local Scripts = require("lib.scripts") --- @class Scripts
local Submap = require("lib.key.submap") --- @class Submap
local Launcher = require("extensions.auto_launcher.launcher") ---@class Launcher

-- The actions the rows name.
require("lib.actions.defs.launch")
require("lib.actions.defs.pickers")
require("lib.actions.defs.tools")

local KEEP = { keep = true }

Submap.define({
  name = "Leader",
  desc = "+Leader",
  enter = Config.leader .. " + SPACE",

  escape = "reset",
  catchall = "reset",

  binds = function()
    -- Rows name actions by id; a label here replaces the action's own, as the submap labels are shorter.
    local binds = {
      -- stylua: ignore start
      -- Pickers
      { "SPACE",         "picker.agents" },
      { "SLASH",         "picker.directory",                              "Directory" },
      { "O",             "menu.drun" },
      { "SHIFT + O",     Launcher.show_picker,                            "Session Launcher" },
      { "CTRL + V",      "picker.clipboard",                              "Clipboard" },
      { "TAB",           "overview.open",                                 "Workspace Overview" },
      { "SHIFT + TAB",   "tmux.overview",                                 "Tmux Overview" },
      { "E",             "picker.emoji",                                  "Emoji" },

      -- Commands
      { "PERIOD",        "voice.dictate" },
      { "COMMA",         "voice.command" },
      { "SHIFT + COMMA", "voice.stop" },
      { "CTRL + COMMA",  "voice.rapid" },
      { "CTRL + PERIOD", "voice.wake" },
      -- SHIFT + SLASH would read as help, but every submap keeps it for the which-key toggle.
      { "CTRL + SLASH",  Cmd.run(Scripts.voxcmd_help),                    "Voice Help" },

      -- Submaps
      { "G",             { "submap.enter", { "Groups" } },                "+Groups",        KEEP },
      -- stylua: ignore end
    }

    for _, row in ipairs(BarRows.binds({ S = BarRows.row("S", "settings", "Settings") })) do
      table.insert(binds, row)
    end
    return binds
  end,
}).setup()
