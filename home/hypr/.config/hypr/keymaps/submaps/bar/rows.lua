--- Bar popup key rows, shared by the Bar submap and the Leader submap's popup keys.

-- The actions the rows name; Bar and Leader only require this module.
require("lib.actions.defs.popups")
require("lib.actions.defs.system")

--- @class BarRows
local BarRows = {}

--- A row that opens a bar popup by name.
--- @param key   string
--- @param name  string
--- @param label string
--- @return table
function BarRows.row(key, name, label) return { key, { "popup.open", { name } }, label } end

--- Return bind rows for every popup key; `overrides` replaces rows by key.
--- @param overrides? table<string, table>
--- @return table[]
function BarRows.binds(overrides)
  overrides = overrides or {}
  local rows = {
    { "A", "menu.agents", "Agents" },
    BarRows.row("B", "bluetooth", "Bluetooth"),
    BarRows.row("C", "clock", "Calendar"),
    BarRows.row("I", "network", "Network and Internet"),
    BarRows.row("M", "media", "Media"),
    BarRows.row("N", "notifications", "Notifications"),
    BarRows.row("P", "battery", "Power and Brightness"),
    BarRows.row("Q", "system", "System"),
    BarRows.row("S", "start", "Start Menu"),
    BarRows.row("T", "tray", "Tray"),
    { "U", "system.update", "Updates" },
    BarRows.row("V", "volume", "Volume"),
    BarRows.row("W", "weather", "Weather"),
  }
  for i, row in ipairs(rows) do
    rows[i] = overrides[row[1]] or row
  end
  return rows
end

return BarRows
