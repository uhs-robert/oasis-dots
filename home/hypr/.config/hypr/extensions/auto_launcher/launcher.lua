-- home/hypr/.config/hypr/extensions/auto_launcher/launcher.lua
local Config = require("config") ---@class Config
local Monitors = require("config.monitors") ---@class Monitors
local Sessions = require("extensions.auto_launcher.sessions") ---@class Sessions
local Prompt = require("lib.prompt") ---@class Prompt

--- @type table<string, HL.WindowRule>
local RULES = {}
local WS_PER_MONITOR = Config.ws_per_monitor

--- @param monitor integer  1-based monitor index; a disconnected one folds onto the highest connected
--- @param offset integer   1-based workspace offset within the monitor's range
--- @return integer
local function ws(monitor, offset) return (Monitors.resolve_slot(monitor) - 1) * WS_PER_MONITOR + offset end

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

--- @param address string
--- @return { x: number, y: number }|nil
local function current_size(address)
  for _, w in ipairs(hl.get_windows() or {}) do
    if w.address == address then return w.size end
  end
end

--- Resizes a window to `size` ({w, h}).
--- A tiled window's relative resize moves its free edge, so a window against the bottom or right of the monitor
--- shrinks on a positive delta. The new size reads back right after the dispatch; any axis that moved away from the
--- target is reversed.
--- @param address string
--- @param size [integer, integer]
local function resize_to(address, size)
  local start_size = current_size(address)
  if not start_size then return end
  local window = "address:" .. address
  local dx, dy = size[1] - start_size.x, size[2] - start_size.y
  hl.dispatch(hl.dsp.window.resize({ window = window, x = dx, y = dy, relative = true }))

  local result_size = current_size(address)
  if not result_size then return end
  -- An axis that went the wrong way moved by -d; twice d in the opposite direction lands it on the target.
  local correction_x = math.abs(size[1] - result_size.x) > math.abs(dx) and -2 * dx or 0
  local correction_y = math.abs(size[2] - result_size.y) > math.abs(dy) and -2 * dy or 0
  if correction_x ~= 0 or correction_y ~= 0 then
    hl.dispatch(hl.dsp.window.resize({ window = window, x = correction_x, y = correction_y, relative = true }))
  end
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
        if app.size then resize_to(w.address, app.size) end
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

--- @class Launcher
local Launcher = {}

---Open a session picker and launch the chosen session; sessions are read at pick time.
function Launcher.show_picker()
  local sessions = Sessions.get_sessions()
  local names = {}
  for k in pairs(sessions) do
    names[#names + 1] = k
  end
  table.sort(names)

  Prompt.select("Session", names, function(choice)
    local apps = choice and sessions[choice]
    if apps then run(apps) end
  end)
end

return Launcher
