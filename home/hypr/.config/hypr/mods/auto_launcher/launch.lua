#!/usr/bin/env lua
-- home/hypr/.config/hypr/mods/auto_launcher/launcher.lua
-- Workspace app launcher subprocess. Shows a rofi session picker and launches the chosen setup.
-- Usage: launcher.lua [ws_per_monitor]

local script_dir = debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./"
package.path = script_dir .. "?.lua;" .. package.path

local setups = require("sessions") ---@type Sessions
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
  if not handle then return end
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

--- Runs a setup: launches each app on its specified monitor workspace.
--- Apps with a `class` field trigger a dynamic workspace rule in the Hyprland context
--- that disables itself once the window appears.
--- @param apps AppEntry[]
local function run(apps)
  for _, app in ipairs(apps) do
    local m = assert(app.monitor, "app entry missing monitor index")
    local workspace = ws(m, app.ws or 1)
    local match_key = app.class and "class" or app.title and "title"
    if match_key then
      local safe = (app.class or app.title):gsub('"', '\\"')
      os.execute(string.format("hyprctl eval 'enable_workspace_rule(\"%s\", \"%s\", %d)'", match_key, safe, workspace))
    end
    launch(app.cmd, workspace)
  end
end

local choice = pick(setups.sessions, "Session")
if choice then run(setups.sessions[choice]) end
