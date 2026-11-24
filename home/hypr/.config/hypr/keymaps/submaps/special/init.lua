--- Special submap
--- One key per special workspace declared in Config.special_workspaces: the key toggles it, SHIFT + key sends there

local Config = require("config") --- @class Config
local Submap = require("lib.key.submap") --- @class Submap

-- The actions the rows name.
require("lib.act.defs.windows")

Submap.define({
  name = "Special",
  desc = "+Special",
  enter = Config.leader .. " + MINUS",

  escape = "reset",
  catchall = "reset",

  binds = function()
    local names = {}
    for name in pairs(Config.special_workspaces) do
      names[#names + 1] = name
    end
    table.sort(names, function(a, b) return Config.special_workspaces[a].key < Config.special_workspaces[b].key end)

    local binds = {}
    for _, name in ipairs(names) do
      local spec = Config.special_workspaces[name]
      binds[#binds + 1] = { spec.key, { "special.toggle", { name } }, spec.label }
      binds[#binds + 1] = { "SHIFT + " .. spec.key, { "special.move", { name } }, "Move to " .. spec.label }
    end
    return binds
  end,
}).setup()
