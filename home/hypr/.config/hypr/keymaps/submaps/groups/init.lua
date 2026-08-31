--- Window groups submap

local Config = require("config") ---@class Config
local Direction = require("lib.key.direction") ---@class Direction
local Submap = require("lib.key.submap") ---@class Submap
local Window = require("lib.actions.window") ---@class WindowActions

Submap.define({
  name = "Groups",
  desc = "+Groups",
  enter = Config.leader .. " + SHIFT + G",

  escape = "reset",
  catchall = "stay",

  binds = function()
    local focus_actions = {
      left = Window.focus_dir("l"),
      down = Window.focus_dir("d"),
      up = Window.focus_dir("u"),
      right = Window.focus_dir("r"),
    }

    local move_actions = {
      left = Window.group_move_or_create("l"),
      down = Window.group_move_or_create("d"),
      up = Window.group_move_or_create("u"),
      right = Window.group_move_or_create("r"),
    }

    local wk_toggle = function() require("lua.plugins.hyprvim").whichkey.toggle() end

    -- stylua: ignore start
    local keys = {
      { "SPACE",                          Window.group_toggle(),      "Toggle Group" },
      { { "TAB", "BRACKETRIGHT" },        Window.group_next(),        "Next Group Window" },
      { { "SHIFT + TAB", "BRACKETLEFT" }, Window.group_prev(),        "Previous Group Window" },
      { "X",                              Window.group_move_out(),    "Move Out of Group" },
      { "SHIFT + X",                      Window.group_lock_toggle(), "Toggle Group Lock" },
      { "SHIFT + SLASH",                  wk_toggle,                  "WhichKey" },
    }
    -- stylua: ignore end

    for _, key in ipairs(Direction.binds(focus_actions, "Focus")) do
      keys[#keys + 1] = key
    end
    for _, key in ipairs(Direction.binds(move_actions, "Group", "SHIFT")) do
      keys[#keys + 1] = key
    end

    return keys
  end,
}).setup()
