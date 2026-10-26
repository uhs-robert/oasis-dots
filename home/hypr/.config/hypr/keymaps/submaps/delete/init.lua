--- Delete submap
--- Destructive window/session actions organized around the verb "destroy/close"

local Config = require("config") --- @class Config
local Submap = require("lib.key.submap") --- @class Submap

-- The actions the rows name.
require("lib.actions.defs.delete")
require("lib.actions.defs.notifications")
require("lib.actions.defs.windows")

--- A row action that closes every window of an app group.
--- @param group string
--- @return table
local function close_group(group) return { "delete.close_group", { group } } end

Submap.define({
  name = "Delete",
  desc = "+Delete",
  enter = Config.leader .. " + D",

  escape = "reset",
  catchall = "reset",

  -- stylua: ignore start
  binds = {
    { "B",          close_group("browsers"),                              "Close Browsers"           },
    { "C",          "delete.clear_clipboard" },
    { "D",          { "delete.close_workspace" },                         "Close All on WS"          },
    { "SHIFT + D",  { "delete.close_workspace", { true } },               "Kill All on WS"           },
    { "E",          close_group("editors"),                               "Close Editors"            },
    { "F",          close_group("files"),                                 "Close File Managers"      },
    { "G",          close_group("games"),                                 "Close Games"              },
    { "M",          close_group("mail"),                                  "Close Mail"               },
    { "N",          "notifications.clear_all" },
    { "O",          { "delete.close_workspace", { false, true } },        "Close Others on WS"       },
    { "SHIFT + O",  { "delete.close_workspace", { true, true } },         "Kill Others on WS"        },
    { "P",          close_group("media"),                                 "Close Media Players"      },
    { "S",          close_group("chat"),                                  "Close Chat"               },
    { "T",          close_group("terminals"),                             "Close Terminals"          },
    { "W",          "window.close" },
    { "SHIFT + W",  "window.kill" },
  },
  -- stylua: ignore end
}).setup()
