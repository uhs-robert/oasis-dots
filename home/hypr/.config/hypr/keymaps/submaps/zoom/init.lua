--- Magnifier Zoom submap
--- Drives the Quickshell zoom loupe and moves the pointer under it

local Config = require("config") ---@class Config
local Scripts = require("lib.scripts") ---@class Scripts
local Submap = require("lib.key.submap") ---@class Submap

local REPEAT = { repeating = true }

---@param args string
---@return fun()
local function zoom(args)
  return function() hl.exec_cmd(Scripts.qs_ipc .. " call zoom " .. args) end
end

---@param dx number
---@param dy number
---@return fun()
local function nudge(dx, dy)
  return function()
    local pos = hl.get_cursor_pos()
    if pos then hl.dispatch(hl.dsp.cursor.move({ x = pos.x + dx, y = pos.y + dy })) end
  end
end

---@return table[]
local function move_binds()
  local keys = { { "h", -1, 0 }, { "j", 0, 1 }, { "k", 0, -1 }, { "l", 1, 0 } }
  local tiers = {
    { "", 10, "10px" },
    { "SHIFT + ", 100, "100px" },
    { "CTRL + ", 1, "1px" },
    { "CTRL + SHIFT + ", 300, "300px" },
  }
  local rows = {}
  for _, tier in ipairs(tiers) do
    for _, k in ipairs(keys) do
      local desc = "Move " .. k[1] .. " " .. tier[3]
      table.insert(rows, { tier[1] .. k[1], nudge(k[2] * tier[2], k[3] * tier[2]), desc, REPEAT })
    end
  end
  return rows
end

local binds = {
  { "i", zoom("step 1"), "Zoom In", REPEAT },
  { "o", zoom("step -1"), "Zoom Out", REPEAT },
  { "bracketright", zoom("size 1"), "Bigger Loupe", REPEAT },
  { "bracketleft", zoom("size -1"), "Smaller Loupe", REPEAT },
  { "f", zoom("full"), "Full Screen" },
}
for _, row in ipairs(move_binds()) do
  table.insert(binds, row)
end

Submap.define({
  name = "Zoom",
  desc = "+Zoom",
  enter = Config.leader .. " + Z",
  on_enter = zoom("start"),
  on_exit = function()
    hl.config({ cursor = { zoom_factor = 1 } })
    zoom("stop")()
  end,

  escape = "reset",
  catchall = "stay",
  binds = binds,
}).setup()
