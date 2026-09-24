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
      { "SLASH",         Menu.zoxide(),                                   "Directory" },
      { "O",             Menu.drun(),                                     "Open Application" },
      { "SHIFT + O",     Launcher.show_picker,                            "Session Launcher" },
      { "V",             Menu.clipboard(),                                "Clipboard" },
      { "E",             Menu.emoji(),                                    "Emoji" },
      { "SHIFT + E",     Menu.emoji("nerd_font"),                         "Nerd Font" },
      { "CTRL + E",      Menu.emoji("gitmoji"),                           "Gitmoji" },
      { "ALT + E",       Menu.emoji("fontawesome"),                       "Font Awesome" },

      -- Commands
      { "PERIOD",        Cmd.run(Scripts.voxtype),                        "Speech to Text" },

      -- Submaps
      { "G",             Submap.switch("Groups"),                         "+Groups",        KEEP },
      -- stylua: ignore end
    }

    local add_row = function(row) table.insert(rows, row) end

    if Config.shell == "quickshell" then
      local function popup(name) return Cmd.run(Scripts.qs_ipc .. " call popup open " .. name) end
      add_row({ "SPACE", popup("start"), "Start Menu" })
      add_row({ "A", popup("keeptabs"), "Agents" })
      add_row({ "B", popup("bluetooth"), "Bluetooth" })
      add_row({ "C", popup("clock"), "Calendar" })
      add_row({ "I", popup("network"), "Network and Internet" })
      add_row({ "M", popup("media"), "Media" })
      add_row({ "N", popup("notifications"), "Notifications" })
      add_row({ "P", popup("battery"), "Power and Brightness" })
      add_row({ "Q", popup("system"), "System" })
      add_row({ "S", popup("start"), "Start Menu" })
      add_row({ "T", popup("tray"), "Tray" })
      add_row({ "U", popup("updates"), "Updates" })
      add_row({ "V", popup("volume"), "Volume" })
      add_row({ "W", popup("weather"), "Weather" })
    else
      add_row({ "SHIFT + N", Submap.switch("Notifications"), "+Notifications", KEEP })
    end

    return rows
  end,
}).setup()
