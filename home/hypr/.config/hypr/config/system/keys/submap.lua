-- home/hypr/.config/hypr/config/system/keys/submap.lua

local Config = require("config")
local LEADER = Config.leader

--- @param keys string Key or key combo to prefix with the leader modifier
--- @return string
local function leader(keys) return LEADER .. " + " .. keys end

--- @class SubmapModule
--- @field map SubmapEntry[]|table<string, SubmapEntry> Indexed array and name-keyed lookup of all registered submaps
--- @field setup fun() Loads all submap definition modules
local Submaps = {}

--- @class SubmapEntry
--- @field name string Hyprland submap name passed to hl.define_submap / hl.dsp.submap
--- @field key string Entry keybind (also used as the exit bind inside the submap)
--- @field fn fun()|nil Optional override action; if nil, defaults to hl.dsp.submap(name)
--- @field defaults { hide: boolean, timeout: number }|nil Saved cursor config, set on entry

--- @type SubmapEntry[] | table<string, SubmapEntry>
Submaps.map = {
  -- stylua: ignore start
  { name = "Applications",  key = leader("A") },
  { name = "Go",            key = leader("G") },
  { name = "Move",          key = leader("M") },
  { name = "Resize",        key = leader("R") },
  { name = "Screenshot",    key = leader("I") },
  { name = "System",        key = leader("Q") },
  { name = "Windows",       key = leader("W") },
  { name = "Cursor",        key = leader("X"),
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
  require("config.system.keys.submaps.go")
  require("config.system.keys.submaps.system")
  require("config.system.keys.submaps.tools")
  require("config.system.keys.submaps.windows")
  require("config.system.keys.submaps.resize_move")
  require("config.system.keys.submaps.cursor")
end

return Submaps
