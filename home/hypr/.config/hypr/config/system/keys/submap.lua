-- home/hypr/.config/hypr/keys/submap.lua

local Config = require("config")

local LEADER = Config.leader .. " "

local Submaps = {}

--- @class SubmapEntry
--- @field name string Hyprland submap name passed to hl.define_submap / hl.dsp.submap
--- @field key string Entry keybind (also used as the exit bind inside the submap)
--- @field fn fun()|nil Optional override action; if nil, defaults to hl.dsp.submap(name)
--- @field defaults { hide: boolean, timeout: number }|nil Saved cursor config, set on entry

--- @type SubmapEntry[] | table<string, SubmapEntry>
Submaps.map = {
  { name = "Applications", key = LEADER .. "+ A" },
  { name = "Go", key = LEADER .. "+ G" },
  { name = "Windows", key = LEADER .. "+ W" },
  { name = "Resize", key = LEADER .. "+ R" },
  { name = "Screenshot", key = LEADER .. "+ I" },
  { name = "System", key = LEADER .. "+ Q" },
  { name = "Move", key = LEADER .. "+ M" },
  {
    name = "Cursor",
    key = LEADER .. "+ X",
    fn = function()
      local sm = Submaps.map.cursor
      sm.defaults = {
        hide = hl.get_config("cursor.hide_on_key_press"),
        timeout = hl.get_config("cursor.inactive_timeout"),
      }
      hl.config({ cursor = { inactive_timeout = 0, hide_on_key_press = false } })
      hl.dispatch(hl.dsp.submap("Cursor"))
    end,
  },
}
for _, sm in ipairs(Submaps.map) do
  Submaps.map[sm.name:lower()] = sm
  hl.bind(sm.key, sm.fn or hl.dsp.submap(sm.name), { description = "+" .. sm.name })
end

Submaps.setup = function()
  require("config.system.keys.submaps.apps")
  require("config.system.keys.submaps.system")
  require("config.system.keys.submaps.tools")
  require("config.system.keys.submaps.windows")
  require("config.system.keys.submaps.resize_move")
  require("config.system.keys.submaps.cursor")
end

return Submaps
