--- Bar popup key rows.
--- Shared by the Bar and Leader submaps; each row names the `popup.open` action.

-- The rows name actions defined here, and the Bar and Leader files only require this module.
require("lib.actions.defs.popups")
require("lib.actions.defs.system")

--- @class Popups
local Popups = {}

--- A row that opens a bar popup by name.
--- @param key   string
--- @param name  string
--- @param label string
--- @return table
function Popups.row(key, name, label) return { key, { "popup.open", { name } }, label } end

--- Return bind rows for every popup key; `overrides` replaces rows by key.
--- @param overrides? table<string, table>
--- @return table[]
function Popups.binds(overrides)
  overrides = overrides or {}
  local rows = {
    { "A", "menu.agents", "Agents" },
    Popups.row("B", "bluetooth", "Bluetooth"),
    Popups.row("C", "clock", "Calendar"),
    Popups.row("I", "network", "Network and Internet"),
    Popups.row("M", "media", "Media"),
    Popups.row("N", "notifications", "Notifications"),
    Popups.row("P", "battery", "Power and Brightness"),
    Popups.row("Q", "system", "System"),
    Popups.row("S", "start", "Start Menu"),
    Popups.row("T", "tray", "Tray"),
    { "U", "system.update", "Updates" },
    Popups.row("V", "volume", "Volume"),
    Popups.row("W", "weather", "Weather"),
  }
  for i, row in ipairs(rows) do
    rows[i] = overrides[row[1]] or row
  end
  return rows
end

return Popups
