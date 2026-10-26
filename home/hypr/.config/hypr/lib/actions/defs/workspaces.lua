-- Actions for the workspace keys. With `Config.persistent_workspaces` the same ids act on the active monitor's own
-- slots, so a key never needs to know which mode is on. No default keys: keymaps/global/workspace.lua binds them with
-- Act.bind, because the slot count and the key set follow Config.
local Act = require("lib.act") ---@class ActionLib

--- @return boolean
local function per_monitor() return require("config").persistent_workspaces and true or false end

Act.define("workspace.focus", {
  label = "Go to Workspace",
  intent = "Go to workspace n, or to slot n of this monitor with persistent workspaces.",
  params = { { name = "n", type = "int" } },
  run = function(n)
    local Workspace = require("lib.actions.workspace")
    if per_monitor() then
      Workspace.focus_local(n)()
    else
      Workspace.focus(n)()
    end
  end,
})

Act.define("workspace.move", {
  label = "Move to Workspace",
  intent = "Move the focused window to workspace n, or to slot n of this monitor with persistent workspaces.",
  params = { { name = "n", type = "int" } },
  run = function(n)
    local Workspace = require("lib.actions.workspace")
    if per_monitor() then
      Workspace.move_local(n)()
    else
      Workspace.move(n)()
    end
  end,
})

Act.define("workspace.cycle", {
  label = "Cycle Workspace",
  intent = "Go to the previous or next workspace (on this monitor with persistent workspaces).",
  params = { { name = "dir", type = "enum", values = { "prev", "next" } } },
  run = function(dir)
    local Workspace = require("lib.actions.workspace")
    if per_monitor() then
      Workspace.cycle_local(dir)()
    elseif dir == "next" then
      Workspace.cycle_next()()
    else
      Workspace.cycle_prev()()
    end
  end,
})

Act.define("workspace.move_window", {
  label = "Move Window to Workspace",
  intent = "Move the focused window to the previous or next workspace (on this monitor with persistent workspaces).",
  params = { { name = "dir", type = "enum", values = { "prev", "next" } } },
  run = function(dir)
    local Workspace = require("lib.actions.workspace")
    if per_monitor() then
      Workspace.move_window_local(dir)()
    elseif dir == "next" then
      Workspace.move_next()()
    else
      Workspace.move_prev()()
    end
  end,
})
