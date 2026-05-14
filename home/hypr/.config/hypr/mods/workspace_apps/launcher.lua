#!/usr/bin/env lua
-- Workspace app launcher subprocess. Shows a rofi session picker and launches the chosen setup.
-- Usage: launcher.lua [ws_per_monitor]

local script_dir = debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./"
package.path = script_dir .. "?.lua;" .. package.path

--- @class AppEntry
--- @field monitor integer 1-based monitor index
--- @field cmd string shell command to launch
--- @field next boolean|nil advance this monitor's workspace counter after launching

local setups = require("setups")
local WS_PER_MONITOR = tonumber(arg[1]) or 5

--- Returns the absolute workspace number for a monitor at a given offset.
--- @param monitor integer 1-based monitor index (matches Config.monitors order)
--- @param offset integer 1-based workspace offset within that monitor's range
--- @return integer
local function ws(monitor, offset) return (monitor - 1) * WS_PER_MONITOR + offset end

--- Shows a sorted rofi dmenu and returns the chosen item, or nil if cancelled.
--- @param items table<string, any> keys become the menu entries
--- @param prompt string
--- @return string|nil
local function pick(items, prompt)
  local keys = {}
  for k in pairs(items) do
    keys[#keys + 1] = k
  end
  table.sort(keys)
  local tmp = os.tmpname()
  local f = assert(io.open(tmp, "w"))
  f:write(table.concat(keys, "\n"))
  f:close()
  local handle = io.popen(string.format("cat %q | rofi -i -dmenu -p %q", tmp, prompt))
  local choice = handle:read("*l")
  handle:close()
  os.remove(tmp)
  return (choice and choice ~= "") and choice or nil
end

--- Launches a command silently on a specific workspace via the Hyprland Lua dispatch API.
--- @param cmd string shell command to execute
--- @param workspace integer absolute workspace number
local function launch(cmd, workspace)
  local safe = cmd:gsub('"', '\\"')
  os.execute(
    string.format(
      "hyprctl dispatch 'hl.dsp.exec_cmd(\"%s\", { workspace = %d, no_initial_focus = true })'",
      safe,
      workspace
    )
  )
end

--- Runs a setup: launches each app on the specified monitor workspace.
--- Monitors start at offset 1. next=true advances the offset after launching.
--- @param apps AppEntry[]
local function run(apps)
  local offsets = {}
  for _, app in ipairs(apps) do
    local m = assert(app.monitor, "app entry missing monitor index")
    offsets[m] = offsets[m] or 1
    launch(app.cmd, ws(m, offsets[m]))
    if app.next then offsets[m] = offsets[m] + 1 end
  end
end

local choice = pick(setups.setups, "Session")
if choice then run(setups.setups[choice]) end
