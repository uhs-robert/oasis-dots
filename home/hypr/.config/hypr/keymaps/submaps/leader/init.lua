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

local function popup(name) return Cmd.run(Scripts.qs_ipc .. " call popup open " .. name) end

Submap.define({
  name = "Leader",
  desc = "+Leader",
  enter = Config.leader .. " + SPACE",

  escape = "reset",
  catchall = "reset",

  binds = function()
    return {
      -- stylua: ignore start
      -- Pickers
      { "SLASH",         Menu.zoxide(),                                   "Directory" },
      { "O",             Menu.drun(),                                     "Open Application" },
      { "SHIFT + O",     Launcher.show_picker,                            "Session Launcher" },
      { "CTRL + V",      Menu.clipboard(),                                "Clipboard" },
      { "E",             Menu.emoji(),                                    "Emoji" },
      { "SHIFT + E",     Menu.emoji("nerd_font"),                         "Nerd Font" },
      { "CTRL + E",      Menu.emoji("gitmoji"),                           "Gitmoji" },
      { "ALT + E",       Menu.emoji("fontawesome"),                       "Font Awesome" },

      -- Commands
      { "PERIOD",        Cmd.run(Scripts.voxtype),                        "Speech to Text" },

      -- Submaps
      { "G",             Submap.switch("Groups"),                         "+Groups",        KEEP },

      -- Bar popups
      { "SPACE",         popup("start"),                                  "Start Menu" },
      { "A",             popup("keeptabs"),                               "Agents" },
      { "B",             popup("bluetooth"),                              "Bluetooth" },
      { "C",             popup("clock"),                                  "Calendar" },
      { "I",             popup("network"),                                "Network and Internet" },
      { "M",             popup("media"),                                  "Media" },
      { "N",             popup("notifications"),                          "Notifications" },
      { "P",             popup("battery"),                                "Power and Brightness" },
      { "Q",             popup("system"),                                 "System" },
      { "S",             popup("style"),                                  "Style" },
      { "T",             popup("tray"),                                   "Tray" },
      { "U",             popup("updates"),                                "Updates" },
      { "V",             popup("volume"),                                 "Volume" },
      { "W",             popup("weather"),                                "Weather" },
      -- stylua: ignore end
    }
  end,
}).setup()
