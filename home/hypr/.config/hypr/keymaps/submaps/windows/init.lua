--- Windows submap

local Config = require("config") ---@class Config
local Direction = require("lib.key.direction") ---@class Direction
local Submap = require("lib.key.submap") ---@class Submap

-- The actions the rows name.
require("lib.act.defs.launch")
require("lib.act.defs.windows")
require("lib.act.defs.windows_select")
require("lib.act.defs.workspaces")

local function enter_submap(name) return { "submap.enter", { name } } end

Submap.define({
  name = "Windows",
  desc = "+Windows",
  enter = Config.leader .. " + W",

  escape = "reset",
  catchall = "stay",
  targets = true,

  hint = {
    { "Focus", "window.focus", "monitor.focus", { "windows.step_float", label = "Floats" } },
    {
      "Move",
      "windows.move_selected",
      { "workspace.cycle", "windows.workspace_selected", label = "WS" },
      { "windows.workspace_move_selected", label = "WS" },
    },
    {
      "Select",
      { "windows.select_toggle", label = "Select" },
      { "windows.swap_selected", label = "Swap" },
      { "windows.confirm", label = "Confirm" },
    },
    {
      "Window",
      { "windows.close_selected", label = "Close" },
      { "windows.float_selected", label = "Float" },
      { "windows.pseudo_selected", label = "Pseudo" },
      { "windows.split_selected", label = "Split" },
    },
    { "Mode", "submap.enter" },
  },

  binds = function()
    local focus_actions = {
      left = { "window.focus", { "left" } },
      down = { "window.focus", { "down" } },
      up = { "window.focus", { "up" } },
      right = { "window.focus", { "right" } },
    }

    local move_actions = {
      left = { "windows.move_selected", { "left" } },
      down = { "windows.move_selected", { "down" } },
      up = { "windows.move_selected", { "up" } },
      right = { "windows.move_selected", { "right" } },
    }

    local ws_actions = {
      left = { "workspace.cycle", { "prev" } },
      down = { "windows.workspace_selected", { "prev" } },
      up = { "windows.workspace_selected", { "next" } },
      right = { "workspace.cycle", { "next" } },
    }

    -- stylua: ignore start
    local keys = {
      { "R",             enter_submap("Resize"),                        "+Resize" },
      { "M",             enter_submap("Move"),                          "+Move" },
      { "C",             enter_submap("Cursor"),                        "+Cursor" },
      { "BRACKETLEFT",   { "windows.step_float", { "prev" } },          "Prev Float" },
      { "BRACKETRIGHT",  { "windows.step_float", { "next" } },          "Next Float" },
      { "X",             "windows.close_selected",                      "Close Window" },
      { "F",             "windows.float_selected",                      "Toggle Floating" },
      { "P",             "windows.pseudo_selected",                     "Toggle Pseudo" },
      { "MINUS",         "windows.split_selected",                      "Toggle Split" },
      { "RETURN",        "windows.confirm" },
      { "SPACE",         "windows.select_toggle" },
      { "S",             "windows.swap_selected" },
    }
    -- stylua: ignore end

    for _, key in ipairs(Direction.binds(focus_actions, "Focus")) do
      keys[#keys + 1] = key
    end
    for _, key in ipairs(Direction.binds(move_actions, "Move", "SHIFT")) do
      keys[#keys + 1] = key
    end
    for _, key in ipairs(Direction.binds(ws_actions, "Workspace", "CTRL")) do
      keys[#keys + 1] = key
    end

    for i = 1, Config.persistent_workspaces or 10 do
      keys[#keys + 1] =
        { "SHIFT + " .. tostring(i % 10), { "windows.workspace_move_selected", { i } }, "Move to WS " .. i }
    end

    for i = 1, #Config.monitors > 0 and math.min(#Config.monitors, 10) or 10 do
      keys[#keys + 1] = { tostring(i % 10), { "monitor.focus", { i } }, "Monitor " .. i }
    end

    return keys
  end,
}).setup()
