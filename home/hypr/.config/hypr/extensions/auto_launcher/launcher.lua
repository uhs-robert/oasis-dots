-- home/hypr/.config/hypr/extensions/auto_launcher/launcher.lua
local Config = require("config") ---@class Config
local Monitors = require("config.monitors") ---@class Monitors
local Sessions = require("extensions.auto_launcher.sessions") ---@class Sessions
local Provenance = require("extensions.auto_launcher.provenance") ---@class Provenance
local Prompt = require("lib.prompt") ---@class Prompt

--- @type table<string, HL.WindowRule>
local RULES = {}
local WS_PER_MONITOR = Config.ws_per_monitor

--- @param monitor integer  1-based monitor index; a disconnected one folds onto the highest connected
--- @param offset integer   1-based workspace offset within the monitor's range
--- @return integer
local function ws(monitor, offset) return (Monitors.resolve_slot(monitor) - 1) * WS_PER_MONITOR + offset end

--- Target workspace of an entry: a workspace id, or `special:<name>`.
--- @param app AppEntry
--- @return integer|string
local function target_workspace(app)
  if app.special then return "special:" .. app.special end
  return ws(assert(app.monitor, "app entry missing monitor index"), app.ws or 1)
end

--- Creates (once) and enables a named workspace window rule, then disables it after 10s.
--- A `silent` rule leaves focus alone; sequenced launches need the new window to take focus.
--- @param match_key "class"|"title"
--- @param match_value string
--- @param workspace integer|string
--- @param silent boolean
local function enable_workspace_rule(match_key, match_value, workspace, silent)
  local key = match_key .. "-" .. match_value .. "-" .. tostring(workspace) .. (silent and "" or "-focus")
  if not RULES[key] then
    RULES[key] = hl.window_rule({
      name = "workspace-app-" .. key:gsub("[^%w%-]", "-"),
      match = { [match_key] = match_value },
      workspace = tostring(workspace) .. (silent and " silent" or ""),
    })
    RULES[key]:set_enabled(false)
  end
  RULES[key]:set_enabled(true)
  hl.timer(function() RULES[key]:set_enabled(false) end, { timeout = 10000, type = "oneshot" })
end

--- @param app AppEntry
--- @param workspace integer|string
--- @param takes_focus boolean
local function launch(app, workspace, takes_focus)
  local rules = { workspace = type(workspace) == "string" and workspace .. " silent" or workspace }
  if not takes_focus then rules.no_initial_focus = true end
  hl.dispatch(hl.dsp.exec_cmd(app.cmd, rules))
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
--- @return HL.Window|nil
local function find_window(address)
  for _, w in ipairs(hl.get_windows() or {}) do
    if w.address == address then return w end
  end
end

--- Resizes a window to `size` ({w, h}).
--- A tiled window's relative resize moves its free edge, so a window against the bottom or right of the monitor
--- shrinks on a positive delta. The new size reads back right after the dispatch; any axis that moved away from the
--- target is reversed.
--- @param address string
--- @param size [integer, integer]
local function resize_to(address, size)
  local start = find_window(address)
  if not start then return end
  local window = "address:" .. address
  local dx, dy = size[1] - start.size.x, size[2] - start.size.y
  hl.dispatch(hl.dsp.window.resize({ window = window, x = dx, y = dy, relative = true }))

  local result = find_window(address)
  if not result then return end
  -- An axis that went the wrong way moved by -d; twice d in the opposite direction lands it on the target.
  local correction_x = math.abs(size[1] - result.size.x) > math.abs(dx) and -2 * dx or 0
  local correction_y = math.abs(size[2] - result.size.y) > math.abs(dy) and -2 * dy or 0
  if correction_x ~= 0 or correction_y ~= 0 then
    hl.dispatch(hl.dsp.window.resize({ window = window, x = correction_x, y = correction_y, relative = true }))
  end
end

--- Moves a claimed window to its workspace, floats it if asked, then applies size and position.
--- @param app AppEntry
--- @param workspace integer|string
--- @param address string
local function place(app, workspace, address)
  local window = "address:" .. address
  hl.dispatch(hl.dsp.window.move({ window = window, workspace = workspace, follow = false }))
  local current = find_window(address)
  -- Only a toggle is known to exist, so flip it just when the window is still tiled.
  if app.float and current and not current.floating then
    hl.dispatch(hl.dsp.window.float({ action = "toggle", window = window }))
  end
  -- Read before the resize: pos is relative to where the window sat when it was claimed.
  current = find_window(address)
  local start_at = current and { x = current.at.x, y = current.at.y }
  if app.size then resize_to(address, app.size) end
  if app.pos and start_at then
    hl.dispatch(hl.dsp.window.move({
      window = window,
      x = app.pos[1] - start_at.x,
      y = app.pos[2] - start_at.y,
      relative = true,
    }))
  end
end

--- Polls for the app's new window, places it, and records which entry opened it.
--- Backstop for single-instance apps, whose server-owned pid the exec rule can't bind to.
--- `on_done` runs once the window is placed, with its address, or after the poller gives up, with none.
--- @param app AppEntry
--- @param workspace integer|string
--- @param before table<string, boolean> window addresses that existed before this app launched
--- @param claimed table<string, boolean> addresses already claimed by another poller in this run()
--- @param on_done fun(address: string|nil)|nil
local function place_when_ready(app, workspace, before, claimed, on_done)
  local match_val = app.class or app.title
  local match_key = app.class and "class" or "title"
  local attempts = 0
  local t
  t = hl.timer(function()
    attempts = attempts + 1
    for _, w in ipairs(hl.get_windows() or {}) do
      if w[match_key] == match_val and not before[w.address] and not claimed[w.address] then
        claimed[w.address] = true
        t:set_enabled(false)
        place(app, workspace, w.address)
        Provenance.record(w.address, app)
        if on_done then on_done(w.address) end
        return
      end
    end
    if attempts >= 60 then
      t:set_enabled(false)
      if on_done then on_done() end
    end
  end, { timeout = 250, type = "repeat" })
end

--- Launches one entry (after its delay), then calls `on_done` once its window is placed.
--- @param app AppEntry
--- @param claimed table<string, boolean>
--- @param takes_focus boolean
--- @param on_done fun(address: string|nil)|nil
local function start_entry(app, claimed, takes_focus, on_done)
  local workspace = target_workspace(app)
  local match_val = app.class or app.title
  local match_key = app.class and "class" or "title"

  local function do_launch()
    if match_val then enable_workspace_rule(match_key, match_val, workspace, not takes_focus) end
    local before = snapshot_addresses()
    launch(app, workspace, takes_focus)
    if match_val then
      place_when_ready(app, workspace, before, claimed, on_done)
    elseif on_done then
      on_done(nil)
    end
  end

  if app.delay then
    hl.timer(do_launch, { timeout = app.delay, type = "oneshot" })
  else
    do_launch()
  end
end

--- Whether an entry joins the one-at-a-time chain: it must land in the tiling layout of a numbered workspace.
--- @param app AppEntry
--- @return boolean
local function is_chained(app) return not app.float and not app.special end

--- Launches the chained entries one at a time. Each new window takes focus, and the window last placed on the same
--- workspace is refocused first, so dwindle's `force_split = 2` splits the same window on every run. The window that
--- had focus before the session is refocused at the end.
--- @param chain AppEntry[]
--- @param claimed table<string, boolean>
local function run_chain(chain, claimed)
  local original = hl.get_active_window()
  local original_address = original and original.address
  local index = 0
  local last_placed = {} -- workspace id to the address of the window most recently placed there

  local function launch_next()
    index = index + 1
    local app = chain[index]
    if not app then
      if original_address and find_window(original_address) then
        hl.dispatch(hl.dsp.focus({ window = "address:" .. original_address }))
      end
      return
    end
    local workspace = target_workspace(app)
    local previous = last_placed[workspace]
    if previous and find_window(previous) then hl.dispatch(hl.dsp.focus({ window = "address:" .. previous })) end
    start_entry(app, claimed, true, function(address)
      last_placed[workspace] = address or previous
      launch_next()
    end)
  end
  launch_next()
end

--- Runs a session: launches each app on its workspace, applying rules and placement as needed.
--- Sequential sessions launch their tiled entries one at a time, in order; everything else launches at once.
--- @param apps AppEntry[]
--- @param sequential boolean|nil
local function run(apps, sequential)
  -- Shared so two same-class launches can't both claim the same window address.
  local claimed = {}
  local chain = {}
  for _, app in ipairs(apps) do
    if sequential and is_chained(app) then
      chain[#chain + 1] = app
    else
      start_entry(app, claimed, false)
    end
  end
  if #chain > 0 then run_chain(chain, claimed) end
end

--- @class Launcher
local Launcher = {}

---Open a session picker and launch the chosen session; sessions are read at pick time.
function Launcher.show_picker()
  local sessions = Sessions.resolve()
  local names = {}
  for k in pairs(sessions) do
    names[#names + 1] = k
  end
  table.sort(names)

  Prompt.select("Session", names, function(choice)
    local session = choice and sessions[choice]
    if session then run(session.apps, session.sequential) end
  end)
end

return Launcher
