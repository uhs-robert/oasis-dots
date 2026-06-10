--- Magnifier Zoom submap
--- Creates a cursor zoom like a glass magnifier

local Config = require("config") ---@class Config
local Submap = require("lib.key.submap") ---@class Submap

-- Magnifier Zoom
local MAX_ZOOM = 10
local MIN_ZOOM = 1
local ZOOM_TOGGLE_FACTOR = 1.5

---@param offset number | nil
---@return nil
local function zoom(offset)
  local current = hl.get_config("cursor.zoom_factor")
  if offset ~= nil then
    current = current + offset
  elseif current ~= MIN_ZOOM then
    current = MIN_ZOOM
  else
    current = ZOOM_TOGGLE_FACTOR
  end
  current = math.max(MIN_ZOOM, math.min(MAX_ZOOM, current))
  hl.config({ cursor = { zoom_factor = current } })
end

Submap.define({
  name = "Zoom",
  desc = "+Zoom",
  enter = Config.leader .. " + Z",
  on_enter = function() zoom() end,
  on_exit = function() hl.config({ cursor = { zoom_factor = MIN_ZOOM } }) end,

  escape = "reset",
  catchall = "stay",

  -- stylua: ignore start
  binds = {
    { "w", function () zoom(0.5) end, "Zoom In", { repeating = true } },
    { "s", function () zoom(-0.5) end, "Zoom Out", { repeating = true } }
  },
  -- stylua: ignore end
}).setup()
