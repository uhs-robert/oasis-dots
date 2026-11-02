local Act = require("lib.act") ---@class ActionLib
local Config = require("config") ---@class Config
local Direction = require("lib.key.direction") ---@class Direction

require("lib.act.defs.workspaces")

-- The ids are the same with persistent workspaces; only their wording changes. All ten keys are bound either way,
-- since a monitor's count changes with how many monitors are connected and parked workspaces sit past its own.
local ON_MONITOR = Config.persistent_workspaces and " on Monitor" or ""

for slot = 1, 10 do
  local key = slot % 10
  Act.bind("workspace.focus", {
    key = { key = "" .. key, leader = true, universal = true },
    args = { slot },
    desc = "Go to Workspace " .. slot,
  })
  Act.bind("workspace.move", {
    key = { key = "SHIFT + " .. key, leader = true },
    args = { slot },
    desc = "Move to Workspace " .. slot,
  })
end

--- Bind CTRL + a letter/arrow pair; only the key shown for Config.vim_mode gets the description.
--- @param id        string
--- @param letter    string
--- @param arrow     string
--- @param dir       "prev"|"next"
--- @param desc      string
--- @param repeating boolean|nil
local function ctrl_dir(id, letter, arrow, dir, desc, repeating)
  local shown, hidden = Direction.keys(letter, arrow)
  repeating = repeating or nil -- an absent option, not false, as before
  Act.bind(
    id,
    { key = { key = "CTRL + " .. shown, leader = true }, args = { dir }, desc = desc, repeating = repeating }
  )
  Act.bind(
    id,
    { key = { key = "CTRL + " .. hidden, leader = true }, args = { dir }, desc = false, repeating = repeating }
  )
end

ctrl_dir("workspace.cycle", "H", "LEFT", "prev", "Prev WS" .. ON_MONITOR, true)
ctrl_dir("workspace.cycle", "L", "RIGHT", "next", "Next WS" .. ON_MONITOR, true)
ctrl_dir("workspace.move_window", "J", "DOWN", "prev", "Move window to prev WS")
ctrl_dir("workspace.move_window", "K", "UP", "next", "Move window to next WS")
