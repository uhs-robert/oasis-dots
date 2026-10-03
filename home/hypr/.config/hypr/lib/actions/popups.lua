--- Bar popup actions.
--- Shared popup key rows for the Bar and Leader submaps.

local Cmd = require("lib.actions.cmd") ---@class Cmd
local Menu = require("lib.actions.menu") ---@class Menu
local Scripts = require("lib.scripts") ---@class Scripts

--- @class Popups
local Popups = {}

--- Open a Quickshell bar popup by name.
--- @param name string
--- @return fun()
function Popups.open(name) return Cmd.run(Scripts.qs_ipc .. " call popup open " .. name) end

--- Return bind rows for every popup key; `overrides` replaces rows by key.
--- @param overrides? table<string, table>
--- @return table[]
function Popups.binds(overrides)
  overrides = overrides or {}
  local rows = {
    { "A", Menu.agents(), "Agents" },
    { "B", Popups.open("bluetooth"), "Bluetooth" },
    { "C", Popups.open("clock"), "Calendar" },
    { "I", Popups.open("network"), "Network and Internet" },
    { "M", Popups.open("media"), "Media" },
    { "N", Popups.open("notifications"), "Notifications" },
    { "P", Popups.open("battery"), "Power and Brightness" },
    { "Q", Popups.open("system"), "System" },
    { "S", Popups.open("start"), "Start Menu" },
    { "T", Popups.open("tray"), "Tray" },
    { "U", Cmd.run(Scripts.focus_topgrade), "Updates" },
    { "V", Popups.open("volume"), "Volume" },
    { "W", Popups.open("weather"), "Weather" },
  }
  for i, row in ipairs(rows) do
    rows[i] = overrides[row[1]] or row
  end
  return rows
end

return Popups
