--- Matches window corners to the Corner style Quickshell draws and, while its screen frame is on, borders, gaps and flush
--- lone windows to the frame, on the monitors that draw it; restores the owner's own values when Quickshell sends clear
--- or goes. Self-contained (no requires), so the shadow harness can dofile it on its own.

local FRAME_NAMESPACE = "quickshell-frame"
local WATCHDOG_MS = 2000
-- About 6 s without a frame layer: longer than a Quickshell reload takes to map the new one.
local MISSES_BEFORE_RESTORE = 3
-- Hyprland caps `rounding` at 20, and the rounding of a rounding_power 1 window is twice its chamfer leg.
local MAX_ROUNDING = 20

-- What was in force before a frame took over, nil while none does. Held here rather than in Quickshell, so a
-- Quickshell restart never mistakes the frame's values for the owner's own. A reload rebuilds this Lua state and
-- the config, which is why Quickshell re-sends on configreloaded.
local saved = nil
local missed_checks = 0
local watchdog = nil
-- Whether the frame is drawn (set's `frame`), as opposed to Quickshell only asking for its Corner style: the watchdog
-- then looks for the frame's layer or, with no frame, for Quickshell's process. Quickshell can run with no layer at
-- all (bars off, no popup), so a layer cannot tell it from a dead one.
local frame_drawn = true
local quickshell_pid = nil
-- Whether a lone tiled window sits flush with the frame (the Settings "Flush single windows" row). Off, it keeps the
-- gaps and rounding of any other window; maximizing stays flush either way.
local flush_lone_windows = true
-- One window rule per rounding value and match, made on first use: a rule's values cannot change, and only the enabled
-- ones apply. Enabling and disabling re-applies to open windows.
local window_rules = {}
-- Workspaces whose lone window the owner took out of the flush look, workspace id -> that window's address, with the
-- per-workspace rule that gives the gaps back and the tag the lone-window rounding rule skips.
local gapped_lones = {}
-- One rule per workspace id and gaps_out value, since a rule's values cannot change; only the one for the gap in force is enabled.
local gap_rules = {}
local active_gap_rules = {}
-- The monitor each opted-out lone window's workspace was on, workspace id -> monitor name: a move to another monitor ends it.
local gapped_lone_monitors = {}
local GAPPED_TAG = "frame_gapped"
-- lib/selection.lua's tag for a selected window, copied as this file has no requires.
local SELECTED_TAG = "targets_selected"
-- The monitors that draw the frame, as Hyprland monitor strings ("desc:<description>" or a connector name), or nil for
-- every monitor: an older Quickshell sends no list. The frame look goes only to these, through an m[] selector on each
-- rule, so Hyprland itself follows a workspace that moves monitor and a monitor that is plugged back in.
local framed_monitors = nil
-- One lone-window flush rule per framed monitor, made on first use like the window rules.
local monitor_lone_rules = {}

--- The smallest gap between tiled windows and the usable area's edge.
--- @return number
local function gaps_out()
  local gaps = hl.get_config("general.gaps_out")
  if type(gaps) == "number" then return gaps end
  local smallest = nil
  if type(gaps) == "table" then
    for _, side in pairs(gaps) do
      if type(side) == "number" and (smallest == nil or side < smallest) then smallest = side end
    end
  end
  return smallest or 0
end

--- A string that differs whenever any edge of the owner's gaps_out does, for keying rules made from the full value.
--- @param gaps number|table
--- @return string
local function gaps_key(gaps)
  if type(gaps) ~= "table" then return tostring(gaps) end
  local sides = {}
  for side, value in pairs(gaps) do
    table.insert(sides, tostring(side) .. "=" .. tostring(value))
  end
  table.sort(sides)
  return table.concat(sides, ",")
end

local function frame_mapped()
  for _, layer in ipairs(hl.get_layers({ namespace = FRAME_NAMESPACE }) or {}) do
    if layer.mapped then return true end
  end
  return false
end

--- Whether `pid` is still a running Quickshell (`qs` or `quickshell`, also `qs-shadow`): a pid reused by another
--- program or a zombie counts as gone, as do a missing or invalid pid, so the corner is never left stuck.
--- @param pid number|nil
--- @return boolean
local function process_alive(pid)
  if type(pid) ~= "number" or pid < 1 then return false end
  local handle = io.open("/proc/" .. math.floor(pid) .. "/stat", "r")
  if handle == nil then return false end
  local stat = handle:read("l") or ""
  handle:close()
  -- "pid (comm) state ...": comm may hold spaces and parentheses, so take the last ")" on the line.
  local comm, state = stat:match("^%d+ %((.*)%) (%a)")
  if comm == nil or state == "Z" then return false end
  return comm:sub(1, 2) == "qs" or comm:sub(1, 10) == "quickshell"
end

-- Workspace rules that drop the outer gaps so a window sits flush against the frame. `f[1]` matches a workspace with a
-- maximized window and `w[tv1]` one with a single tiled window; Hyprland re-evaluates the selectors on every layout
-- pass, so the gaps come back by themselves when the window unmaximizes, closes, moves away or gets a tiled neighbour.
-- Maximizing is flush with or without a frame; a lone tiled window is flush only inside one. A flush window has no gap
-- to shrink its corner by, so use_window_rules gives it the frame's own radius instead of the gapped windows' smaller one.
hl.workspace_rule({ workspace = "f[1]", gaps_out = 0 })
local lone_window_rule = hl.workspace_rule({ workspace = "w[tv1]", gaps_out = 0 })
lone_window_rule:set_enabled(false)

--- The rule selector for windows or workspaces on `monitor`, or `selector` alone when the frame is on every monitor.
--- @param selector string|nil
--- @param monitor string|nil
--- @return string|nil
local function on_monitor(selector, monitor)
  if monitor == nil then return selector end
  local own = "m[" .. monitor .. "]"
  return selector and (selector .. " " .. own) or own
end

--- Turns the lone-window flush on for exactly `monitors` (nil: on every monitor through the global rule), or off.
--- @param on boolean
--- @param monitors string[]|nil
local function use_lone_rules(on, monitors)
  lone_window_rule:set_enabled(on and monitors == nil)
  local wanted = {}
  for _, monitor in ipairs((on and monitors) or {}) do
    wanted[monitor] = true
    if not monitor_lone_rules[monitor] then
      monitor_lone_rules[monitor] = hl.workspace_rule({ workspace = on_monitor("w[tv1]", monitor), gaps_out = 0 })
      -- Of two matching workspace rules the later one wins, so an opt-out gaps rule made before this one would lose to
      -- it: the next opt-out makes a fresh one.
      gap_rules = {}
    end
    monitor_lone_rules[monitor]:set_enabled(true)
  end
  for monitor, rule in pairs(monitor_lone_rules) do
    if not wanted[monitor] then rule:set_enabled(false) end
  end
end

--- Whether `monitor` (a Hyprland monitor object) draws the frame, as `framed_monitors` names it.
--- @param monitor table|nil
--- @return boolean
local function monitor_framed(monitor)
  if framed_monitors == nil then return true end
  if monitor == nil then return false end
  for _, key in ipairs(framed_monitors) do
    local description = key:match("^desc:(.*)$")
    if description then
      -- Hyprland's own desc: match is a prefix match too.
      if tostring(monitor.description or ""):sub(1, #description) == description then return true end
    elseif key == monitor.name then
      return true
    end
  end
  return false
end

--- The framed monitor list from set's argument: strings usable inside an m[] selector, nil for anything else.
--- @param monitors any
--- @return string[]|nil
local function framed_list(monitors)
  if type(monitors) ~= "table" then return nil end
  local list = {}
  for _, monitor in ipairs(monitors) do
    if type(monitor) == "string" and monitor ~= "" and not monitor:find("]", 1, true) then
      table.insert(list, monitor)
    end
  end
  return list
end

--- Enables exactly the rules in `wanted` (made on first use), disabling every other.
--- @param wanted table[] each { kind, monitor?, rounding, power } or { kind = "border", monitor?, border_size?,
---   border_color? }; kind says which windows: "gapped" and "border" (all), "lone" (the only tiled window on its
---   workspace) or "maximized"; monitor limits it to windows on that monitor
local function use_window_rules(wanted)
  local wanted_names = {}
  for _, spec in ipairs(wanted) do
    local values = spec.kind == "border" and { spec.border_size or "", spec.border_color or "" }
      or { spec.rounding, spec.power }
    local name = "quickshell-frame-" .. spec.kind .. "-" .. table.concat(values, "-")
    if spec.monitor then name = name .. "-" .. spec.monitor end
    wanted_names[name] = true
    if not window_rules[name] then
      local match = { class = ".*" }
      if spec.kind == "lone" then
        match.workspace = on_monitor("w[tv1]", spec.monitor)
        match.float = false
        match.tag = "negative:" .. GAPPED_TAG
      else
        match.workspace = on_monitor(nil, spec.monitor)
        if spec.kind == "maximized" then match.fullscreen_state_internal = "1" end
        -- Made after lib/selection.lua's rule, this one would win; the selection border must show on a selected window.
        if spec.kind == "border" then match.tag = "negative:" .. SELECTED_TAG end
      end
      local rule = { name = name, match = match }
      if spec.kind == "border" then
        rule.border_size, rule.border_color = spec.border_size, spec.border_color
      else
        rule.rounding, rule.rounding_power = spec.rounding, spec.power
      end
      window_rules[name] = hl.window_rule(rule)
    end
    window_rules[name]:set_enabled(true)
  end
  for name, rule in pairs(window_rules) do
    if not wanted_names[name] then rule:set_enabled(false) end
  end
end

--- The tiled windows on a workspace, the ones the `w[tv1]` selector counts.
--- @param workspace_id integer
--- @return table[]
local function tiled_windows(workspace_id)
  local tiled = {}
  for _, window in ipairs(hl.get_workspace_windows(workspace_id) or {}) do
    if window.mapped and window.visible ~= false and not window.floating then table.insert(tiled, window) end
  end
  return tiled
end

local function has_gapped_tag(window)
  local tags = window.tags
  if type(tags) ~= "table" then return tostring(tags):find(GAPPED_TAG, 1, true) ~= nil end
  for _, tag in pairs(tags) do
    if tostring(tag):find(GAPPED_TAG, 1, true) then return true end
  end
  return false
end

local function tag_window(address, on)
  hl.dispatch(hl.dsp.window.tag({ tag = (on and "+" or "-") .. GAPPED_TAG, window = "address:" .. address }))
end

local function release_gapped_lone(workspace_id)
  local address = gapped_lones[workspace_id]
  if address == nil then return end
  gapped_lones[workspace_id] = nil
  gapped_lone_monitors[workspace_id] = nil
  if active_gap_rules[workspace_id] then active_gap_rules[workspace_id]:set_enabled(false) end
  active_gap_rules[workspace_id] = nil
  tag_window(address, false)
end

--- The name of the monitor a window's workspace is on, nil when Hyprland does not say.
local function workspace_monitor(window)
  local monitor = window.workspace and window.workspace.monitor
  return monitor and monitor.name
end

--- Gives every opted-out lone window its flush look back once it is no longer alone on its workspace (a second tiled
--- window arrived, it closed, moved or floated) or the workspace went to another monitor, and drops a tag whose
--- opt-out this Lua state no longer holds (a config reload rebuilds the state but not the tags).
local function release_stale_gapped_lones()
  for workspace_id, address in pairs(gapped_lones) do
    local tiled = tiled_windows(workspace_id)
    local alone = #tiled == 1 and tiled[1].address == address
    local moved = alone and workspace_monitor(tiled[1]) ~= gapped_lone_monitors[workspace_id]
    if not flush_lone_windows or not alone or moved then release_gapped_lone(workspace_id) end
  end
  for _, window in ipairs(hl.get_windows() or {}) do
    local held = window.workspace and gapped_lones[window.workspace.id] == window.address
    if not held and has_gapped_tag(window) then tag_window(window.address, false) end
  end
end

--- The workspace switch animation as the config defines it (`_G.WorkspacesAnimation`, from config/rules) or, with the
--- frame on, a plain slide on a bezier that does not overshoot: flush windows would visibly bounce past the frame and
--- snap back. The curve and `_G.WorkspacesAnimation` come from config/rules at load; if a frame is set before that
--- (`_G.WorkspacesAnimation` still nil), this returns early and leaves Hyprland's animation untouched.
--- Hyprland cannot read an animation back, so the restore replays the config's own spec.
--- @param frame_on boolean
local function apply_workspaces_animation(frame_on)
  local base = _G.WorkspacesAnimation
  if base == nil then return end
  local spec = {}
  for key, value in pairs(base) do
    spec[key] = value
  end
  if frame_on then
    spec.style = "slide"
    spec.speed = 3.5
    spec.bezier = "easeOutQuint"
  end
  hl.animation(spec)
end

local function restore()
  for workspace_id in pairs(gapped_lones) do
    release_gapped_lone(workspace_id)
  end
  use_lone_rules(false)
  framed_monitors = nil
  if watchdog then watchdog:set_enabled(false) end
  quickshell_pid = nil
  if saved == nil then return end
  use_window_rules({})
  apply_workspaces_animation(false)
  hl.config({
    decoration = { rounding = saved.rounding, rounding_power = saved.rounding_power },
    general = {
      border_size = saved.border_size,
      col = { active_border = saved.active_border, inactive_border = saved.inactive_border },
    },
  })
  saved = nil
end

-- Quickshell sends clear when the frame goes, but a crashed or quit Quickshell sends nothing, so the frame's layer
-- (or, with no frame, Quickshell's process) going missing restores too.
local function check_frame()
  if (frame_drawn and frame_mapped()) or (not frame_drawn and process_alive(quickshell_pid)) then
    missed_checks = 0
    return
  end
  missed_checks = missed_checks + 1
  if missed_checks >= MISSES_BEFORE_RESTORE then restore() end
end

--- The rounding for a window sitting `gaps_out` inside a frame corner of `radius`, in the profile's own shape.
--- Round: a concentric arc. Chamfer and pixel: the chamfer leg shrinks by gap * (2 - sqrt 2) to stay concentric, and
--- a power-1 window's rounding is twice its leg. Square: none.
--- @param corner string
--- @param radius number the corner as drawn (already fitted), px
--- @param gap number
--- @return integer rounding, boolean chamfered
local function window_rounding(corner, radius, gap)
  if corner == "round" then return math.max(0, math.floor(radius - gap)), false end
  if corner == "chamfer" or corner == "pixel" then
    local leg = radius - gap * (2 - math.sqrt(2))
    local rounding = math.min(MAX_ROUNDING, math.floor(2 * leg + 0.5))
    if rounding > 0 then return rounding, true end
  end
  return 0, false
end

--- Shapes windows to the Corner style: `corner` and `radius` give the corner. With the frame on, `border_size` and the
--- two colours set the window borders, the animation becomes the plain slide and a lone window may go flush. With it
--- off only the rounding changes: the owner's borders, gaps and animation stay and no window goes flush. Saves the
--- owner's values first, and keeps them until `clear`. A style with no border (width 0, or "" for an invisible
--- colour) leaves the owner's own border size and colour in place instead of drawing an invisible one.
--- @param corner string round, chamfer, pixel or square
--- @param radius number
--- @param border_size number
--- @param active string a colour Hyprland parses, e.g. "rgba(33ccffee)"
--- @param inactive string
--- @param flush? boolean whether a lone tiled window goes flush with the frame; anything but false means it does
--- @param frame? boolean whether the frame is drawn; anything but false means it is (an older Quickshell sends no such argument)
--- @param pid? number Quickshell's process id, which the watchdog watches while the frame is off
--- @param monitors? string[] the monitors that draw the frame ("desc:<description>" or a connector name); the others
---   keep the owner's rounding, borders and gaps. Without it (an older Quickshell) every monitor does.
local function set(corner, radius, border_size, active, inactive, flush, frame, pid, monitors)
  frame_drawn = frame ~= false
  framed_monitors = frame_drawn and framed_list(monitors) or nil
  quickshell_pid = (not frame_drawn) and tonumber(pid) or nil
  flush_lone_windows = frame_drawn and flush ~= false
  if saved == nil then
    saved = {
      rounding = hl.get_config("decoration.rounding"),
      rounding_power = hl.get_config("decoration.rounding_power"),
      border_size = hl.get_config("general.border_size"),
      active_border = hl.get_config("general.col.active_border"),
      inactive_border = hl.get_config("general.col.inactive_border"),
    }
  end
  local gap = gaps_out()
  local rounding, chamfered = window_rounding(corner, tonumber(radius) or 0, gap)
  local flush_rounding, flush_chamfered = window_rounding(corner, tonumber(radius) or 0, 0)
  -- A chamfered window's own rounding comes from its rule, so the global one only matters for windows the rule misses.
  -- Power 2 keeps a squircle rounding of the owner's from drawing a round window's arc off the frame's circle.
  local width = tonumber(border_size)
  -- Without the frame the borders go back to the owner's, which also undoes a frame that was on a moment ago.
  if not frame_drawn then
    width, active, inactive = nil, nil, nil
  end
  if not (width and width > 0) then width = nil end
  if active == "" then active = nil end
  if inactive == "" then inactive = nil end
  -- The flush power follows the flush corner: a large gap can flatten the gapped corner while the flush one stays cut.
  local power = flush_chamfered and 1 or 2
  local rules = {}
  if framed_monitors == nil then
    hl.config({
      decoration = { rounding = chamfered and 0 or rounding, rounding_power = 2 },
      general = {
        border_size = width or saved.border_size,
        col = {
          active_border = active or saved.active_border,
          inactive_border = inactive or saved.inactive_border,
        },
      },
    })
    if chamfered then table.insert(rules, { rounding = rounding, power = 1, kind = "gapped" }) end
    if frame_drawn and flush_rounding ~= rounding then
      if flush_lone_windows then table.insert(rules, { rounding = flush_rounding, power = power, kind = "lone" }) end
      table.insert(rules, { rounding = flush_rounding, power = power, kind = "maximized" })
    end
  else
    -- The global values stay the owner's for the unframed monitors, and rules give the framed ones the frame's look.
    -- A rule's border colour pair is active then inactive, so an invisible active one leaves both colours alone.
    hl.config({
      decoration = { rounding = saved.rounding, rounding_power = saved.rounding_power },
      general = {
        border_size = saved.border_size,
        col = { active_border = saved.active_border, inactive_border = saved.inactive_border },
      },
    })
    local border_color = active and (inactive and (active .. " " .. inactive) or active) or nil
    for _, monitor in ipairs(framed_monitors) do
      table.insert(rules, { rounding = rounding, power = chamfered and 1 or 2, kind = "gapped", monitor = monitor })
      if width or border_color then
        table.insert(rules, { kind = "border", border_size = width, border_color = border_color, monitor = monitor })
      end
      if flush_rounding ~= rounding then
        if flush_lone_windows then
          table.insert(rules, { rounding = flush_rounding, power = power, kind = "lone", monitor = monitor })
        end
        table.insert(rules, { rounding = flush_rounding, power = power, kind = "maximized", monitor = monitor })
      end
    end
  end
  use_window_rules(rules)
  use_lone_rules(flush_lone_windows, framed_monitors)
  apply_workspaces_animation(frame_drawn)
  release_stale_gapped_lones()
  missed_checks = 0
  if watchdog then
    watchdog:set_enabled(true)
  else
    watchdog = hl.timer(check_frame, { timeout = WATCHDOG_MS, type = "repeat" })
  end
end

--- SUPER+M on a lone tiled window, while the frame is on and lone windows are flush: takes it out of the flush look
--- (the owner's gaps and the gapped rounding) or puts it back. The opt-out is held for that workspace and window only, and release_stale_gapped_lones
--- ends it as soon as the window is no longer alone, so it cannot outlive the situation it was asked for.
--- @return boolean handled false when the caller should maximize as usual
local function toggle_lone_flush()
  local window = hl.get_active_window()
  -- With flush off a lone window is already gapped, so there is nothing to opt out of and the key maximizes.
  if
    saved == nil
    or not flush_lone_windows
    or window == nil
    or window.floating
    or window.fullscreen ~= 0
    or window.workspace == nil
    or not monitor_framed(window.workspace.monitor)
  then
    return false
  end
  local workspace_id = window.workspace.id
  local tiled = tiled_windows(workspace_id)
  if #tiled ~= 1 or tiled[1].address ~= window.address then return false end
  if gapped_lones[workspace_id] then
    release_gapped_lone(workspace_id)
    return true
  end
  -- The rule gets the owner's full value: a per-edge gaps table must not collapse to its smallest side, so the cache
  -- is keyed on every edge too (a per-edge edit without a reload would otherwise reuse a rule with the old edges).
  local gaps = hl.get_config("general.gaps_out")
  local rule_key = workspace_id .. ":" .. gaps_key(gaps)
  if not gap_rules[rule_key] then
    gap_rules[rule_key] = hl.workspace_rule({ workspace = tostring(workspace_id), gaps_out = gaps })
  end
  gap_rules[rule_key]:set_enabled(true)
  active_gap_rules[workspace_id] = gap_rules[rule_key]
  gapped_lones[workspace_id] = window.address
  gapped_lone_monitors[workspace_id] = workspace_monitor(window)
  tag_window(window.address, true)
  return true
end

--- Whether Hyprland has the window.update_state event (0.57 and newer). On 0.56 hl.on raises for an unknown event,
--- which would stop the loop below. Inline rather than lib.key.bind's check, as this file has no requires; both go
--- when 0.56 support ends.
local has_update_state = (function()
  local version = type(hl.version) == "function" and hl.version() or nil
  local major, minor = tostring(version):match("^(%d+)%.(%d+)")
  major, minor = tonumber(major), tonumber(minor)
  return major ~= nil and (major > 0 or minor >= 57)
end)()

local release_events = {
  "window.open",
  "window.update_rules", -- floats and tiles on 0.56; a backstop on 0.57, where a second release is harmless
  "window.close", -- not window.destroy: on logout Hyprland fires that mid-teardown and hl.get_windows() segfaults (#1486)
  "window.move_to_workspace",
  "window.fullscreen",
}
if has_update_state then table.insert(release_events, "window.update_state") end -- a window floats or tiles

for _, event in ipairs(release_events) do
  hl.on(event, function() release_stale_gapped_lones() end)
end

-- Hyprland re-matches workspace rules on every layout pass but window rules only on a window's own events, so a
-- workspace moved to another monitor (by hand, or by a monitor going or coming back) keeps the old monitor's rounding
-- and borders until rules are re-applied, which enabling a rule does. Deferred out of the event, which Hyprland fires
-- mid-move, as a handler reading windows inside Hyprland's own bookkeeping can crash it (#1486).
local refresh_pending = false
local function refresh_monitor_rules()
  refresh_pending = false
  release_stale_gapped_lones()
  if framed_monitors == nil then return end
  for _, rule in pairs(window_rules) do
    if rule:is_enabled() then return rule:set_enabled(true) end
  end
end
-- Not monitor.added or monitor.removed: a monitor going or coming moves its workspaces, which fires this event, and
-- on shutdown Hyprland moves none, so nothing is scheduled mid-teardown.
hl.on("workspace.move_to_monitor", function()
  if refresh_pending or saved == nil then return end
  refresh_pending = true
  hl.timer(refresh_monitor_rules, { timeout = 50, type = "oneshot" })
end)

-- Global functions which are accessible externally via `hyprctl dispatch "ScreenFrame"`
_G.ScreenFrame = {
  set = function(corner, radius, border_size, active, inactive, flush, frame, pid, monitors)
    set(corner, radius, border_size, active, inactive, flush, frame, pid, monitors)

    return hl.dsp.no_op()
  end,
  toggle_lone_flush = toggle_lone_flush,
  clear = function()
    restore()

    return hl.dsp.no_op()
  end,
}
