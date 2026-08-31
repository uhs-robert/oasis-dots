--- Window groups submap

local Config = require("config") ---@class Config
local Submap = require("lib.key.submap") ---@class Submap
local Window = require("lib.actions.window") ---@class WindowActions

Submap.define({
  name = "Groups",
  desc = "+Groups",
  enter = Config.leader .. " + SHIFT + G",

  escape = "reset",
  catchall = "stay",

  binds = function()
    return {
      { "SPACE", Window.group_toggle(), "Toggle Group" },

      { "H", Window.focus_dir("l"), "Focus Left" },
      { "J", Window.focus_dir("d"), "Focus Down" },
      { "K", Window.focus_dir("u"), "Focus Up" },
      { "L", Window.focus_dir("r"), "Focus Right" },

      { "SHIFT + H", Window.group_move_in("l"), "Move Into Group Left" },
      { "SHIFT + J", Window.group_move_in("d"), "Move Into Group Down" },
      { "SHIFT + K", Window.group_move_in("u"), "Move Into Group Up" },
      { "SHIFT + L", Window.group_move_in("r"), "Move Into Group Right" },

      { "TAB", Window.group_next(), "Next Group Window" },
      { "SHIFT + TAB", Window.group_prev(), "Previous Group Window" },
      { "BRACKETRIGHT", Window.group_next(), "Next Group Window" },
      { "BRACKETLEFT", Window.group_prev(), "Previous Group Window" },

      { "X", Window.group_move_out(), "Move Out of Group" },
      { "SHIFT + X", Window.group_lock_toggle(), "Toggle Group Lock" },
    }
  end,
}).setup()
