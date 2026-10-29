--- Window groups submap

local Config = require("config") ---@class Config
local Direction = require("lib.key.direction") ---@class Direction
local Submap = require("lib.key.submap") ---@class Submap

-- The actions the rows name.
require("lib.act.defs.groups")
require("lib.act.defs.windows")

Submap.define({
  name = "Groups",
  desc = "+Groups",
  enter = Config.leader .. " + SHIFT + G",

  escape = "reset",
  catchall = "stay",

  binds = function()
    local focus_actions = {
      left = { "window.focus", { "left" } },
      down = { "window.focus", { "down" } },
      up = { "window.focus", { "up" } },
      right = { "window.focus", { "right" } },
    }

    local move_actions = {
      left = { "groups.move", { "left" } },
      down = { "groups.move", { "down" } },
      up = { "groups.move", { "up" } },
      right = { "groups.move", { "right" } },
    }

    -- stylua: ignore start
    local keys = {
      { "SPACE",                          "groups.toggle" },
      { { "TAB", "BRACKETRIGHT" },        "groups.next" },
      { { "SHIFT + TAB", "BRACKETLEFT" }, "groups.prev" },
      { "X",                              "groups.move_out" },
      { "SHIFT + X",                      "groups.lock_toggle" },
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
