#!/usr/bin/env lua
-- home/hypr/.config/hypr/extensions/auto_launcher/launcher.lua
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

--- Wraps a string in single quotes, escaping any embedded single quotes.
--- @param str string
--- @return string
local function shell_quote(str) return "'" .. tostring(str):gsub("'", [['"'"']]) .. "'" end

--- Formats a string as a quoted Lua string literal suitable for injection into eval'd code.
--- @param str string
--- @return string
local function lua_string(str) return string.format("%q", tostring(str)) end

--- Evaluates a Lua expression in the Hyprland runtime context via `hyprctl eval`.
--- @param code string Lua source to evaluate
--- @return boolean|nil
local function eval(code) return os.execute("hyprctl eval " .. shell_quote(code)) end

--- Schedules a repeating timer in the Hyprland context that polls for the app's window
--- and applies size/position adjustments once it appears.
--- Requires `app.class` or `app.title` to identify the window; no-ops if neither is set.
--- @param app AppEntry
local function resize_when_ready(app)
  local match_val = app.class or app.title
  if not match_val then return end
  local match_key = app.class and "class" or "title"

  local resize_stmt = app.size
      and string.format(
        "hl.dispatch(hl.dsp.window.resize({ window = window, x = w.size.x - %d, y = w.size.y - %d, relative = true }))",
        app.size[1],
        app.size[2]
      )
    or ""

  local move_stmt = app.pos
      and string.format(
        "hl.dispatch(hl.dsp.window.move({ window = window, x = %d - w.at.x, y = %d - w.at.y, relative = true }))",
        app.pos[1],
        app.pos[2]
      )
    or ""

  eval(string.format(
    [[
      local attempts = 0
      local timer
      timer = hl.timer(function()
        attempts = attempts + 1
        for _, w in ipairs(hl.get_windows() or {}) do
          if w[%s] == %s then
            timer:set_enabled(false)
            local window = "address:" .. w.address
            %s
            %s
            return
          end
        end
        if attempts >= 30 then timer:set_enabled(false) end
      end, { timeout = 500, type = "repeat" })
    ]],
    lua_string(match_key),
    lua_string(match_val),
    resize_stmt,
    move_stmt
  ))
end

--- Launches a command silently on a specific workspace via the Hyprland exec dispatcher.
--- @param app AppEntry
--- @param workspace integer absolute workspace number
local function launch(app, workspace)
  eval(
    string.format(
      "hl.dispatch(hl.dsp.exec_cmd(%s, { workspace = %d, no_initial_focus = true }))",
      lua_string(app.cmd),
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
    if app.delay then os.execute(string.format("sleep %.3f", app.delay / 1000)) end
    local match_val = app.class or app.title
    if match_val then
      local match_key = app.class and "class" or "title"
      eval(string.format("enable_workspace_rule(%s, %s, %d)", lua_string(match_key), lua_string(match_val), workspace))
    end
    launch(app, workspace)
    if (app.size or app.pos) and (app.class or app.title) then resize_when_ready(app) end
  end
end

local sessions = setups.get_sessions()
local choice = pick(sessions, "Session")
if choice then run(sessions[choice]) end
