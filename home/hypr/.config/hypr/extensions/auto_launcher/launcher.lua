-- home/hypr/.config/hypr/extensions/auto_launcher/launcher.lua
local Config = require("config") ---@class Config
local Sessions = require("extensions.auto_launcher.sessions") ---@class Sessions
local Prompt = require("lib.prompt") ---@class Prompt

--- @type table<string, HL.WindowRule>
local RULES = {}
local SESSIONS = Sessions.get_sessions()
local WS_PER_MONITOR = Config.ws_per_monitor

--- @param monitor integer  1-based monitor index
--- @param offset integer   1-based workspace offset within the monitor's range
--- @return integer
local function ws(monitor, offset) return (monitor - 1) * WS_PER_MONITOR + offset end

--- Creates (once) and enables a named workspace window rule, then disables it after 30s.
--- @param match_key "class"|"title"
--- @param match_value string
--- @param workspace integer
local function enable_workspace_rule(match_key, match_value, workspace)
  local key = match_key .. "-" .. match_value .. "-" .. tostring(workspace)
  if not RULES[key] then
    RULES[key] = hl.window_rule({
      name = "workspace-app-" .. key:gsub("[^%w%-]", "-"),
      match = { [match_key] = match_value },
      workspace = tostring(workspace) .. " silent",
    })
    RULES[key]:set_enabled(false)
  end
  RULES[key]:set_enabled(true)
  hl.timer(function() RULES[key]:set_enabled(false) end, { timeout = 10000, type = "oneshot" })
end

--- @param app AppEntry
--- @param workspace integer
local function launch(app, workspace)
  hl.dispatch(hl.dsp.exec_cmd(app.cmd, { workspace = workspace, no_initial_focus = true }))
end

--- @return table<string, boolean> set of every currently-open window address
local function snapshot_addresses()
  local addrs = {}
  for _, w in ipairs(hl.get_windows() or {}) do
    addrs[w.address] = true
  end
  return addrs
end

--- Polls for the app's new window, moves it to the target workspace, and applies size/position.
--- Backstop for single-instance apps, whose server-owned pid the exec rule can't bind to.
--- @param app AppEntry
--- @param workspace integer
--- @param before table<string, boolean> window addresses that existed before this app launched
--- @param claimed table<string, boolean> addresses already claimed by another poller in this run()
local function place_when_ready(app, workspace, before, claimed)
  local match_val = app.class or app.title
  if not match_val then return end
  local match_key = app.class and "class" or "title"
  local attempts = 0
  local t
  t = hl.timer(function()
    attempts = attempts + 1
    for _, w in ipairs(hl.get_windows() or {}) do
      if w[match_key] == match_val and not before[w.address] and not claimed[w.address] then
        claimed[w.address] = true
        t:set_enabled(false)
        local window = "address:" .. w.address
        hl.dispatch(hl.dsp.window.move({ window = window, workspace = workspace, follow = false }))
        if app.size then
          hl.dispatch(hl.dsp.window.resize({
            window = window,
            x = w.size.x - app.size[1],
            y = w.size.y - app.size[2],
            relative = true,
          }))
        end
        if app.pos then
          hl.dispatch(hl.dsp.window.move({
            window = window,
            x = app.pos[1] - w.at.x,
            y = app.pos[2] - w.at.y,
            relative = true,
          }))
        end
        return
      end
    end
    if attempts >= 60 then t:set_enabled(false) end
  end, { timeout = 250, type = "repeat" })
end

--- Runs a session: launches each app on its workspace, applying rules and placement as needed.
--- @param apps AppEntry[]
local function run(apps)
  -- Shared so two same-class launches can't both claim the same window address.
  local claimed = {}
  for _, app in ipairs(apps) do
    local workspace = ws(assert(app.monitor, "app entry missing monitor index"), app.ws or 1)
    local match_val = app.class or app.title
    local match_key = app.class and "class" or "title"

    local function do_launch()
      if match_val then enable_workspace_rule(match_key, match_val, workspace) end
      local before = snapshot_addresses()
      launch(app, workspace)
      if match_val then place_when_ready(app, workspace, before, claimed) end
    end

    if app.delay then
      hl.timer(do_launch, { timeout = app.delay, type = "oneshot" })
    else
      do_launch()
    end
  end
end

local names = {}
for k in pairs(SESSIONS) do
  names[#names + 1] = k
end
table.sort(names)

--- @class Launcher
local Launcher = {}

---Open a session picker via preferred menu launcher and launch the chosen session.
function Launcher.show_picker()
  Prompt.select("Session", names, function(choice)
    local apps = choice and SESSIONS[choice]
    if apps then run(apps) end
  end)
end

return Launcher
