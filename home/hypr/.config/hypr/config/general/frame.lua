--- Matches window corners and borders to the screen frame Quickshell draws round the usable area, and restores the
--- owner's own values when the frame goes. Self-contained (no requires), so the shadow harness can dofile it on its own.

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
-- One window rule per rounding value and match, made on first use: a rule's values cannot change, and only the enabled
-- ones apply. Enabling and disabling re-applies to open windows.
local window_rules = {}

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

local function frame_mapped()
  for _, layer in ipairs(hl.get_layers({ namespace = FRAME_NAMESPACE }) or {}) do
    if layer.mapped then return true end
  end
  return false
end

-- Workspace rules that drop the outer gaps so a window sits flush against the frame. `f[1]` matches a workspace with a
-- maximized window and `w[tv1]` one with a single tiled window; Hyprland re-evaluates the selectors on every layout
-- pass, so the gaps come back by themselves when the window unmaximizes, closes, moves away or gets a tiled neighbour.
-- Maximizing is flush with or without a frame; a lone tiled window is flush only inside one. A flush window has no gap
-- to shrink its corner by, so use_window_rules gives it the frame's own radius instead of the gapped windows' smaller one.
hl.workspace_rule({ workspace = "f[1]", gaps_out = 0 })
local lone_window_rule = hl.workspace_rule({ workspace = "w[tv1]", gaps_out = 0 })
lone_window_rule:set_enabled(false)

--- Enables exactly the rules in `wanted` (made on first use), disabling every other.
--- @param wanted table[] each { rounding, power, kind }; kind says which windows: "gapped" (all), "lone" (the only tiled
---   window on its workspace) or "maximized"
local function use_window_rules(wanted)
  local wanted_names = {}
  for _, spec in ipairs(wanted) do
    local name = "quickshell-frame-" .. spec.kind .. "-" .. spec.rounding .. "-" .. spec.power
    wanted_names[name] = true
    if not window_rules[name] then
      local match = { class = ".*" }
      if spec.kind == "lone" then
        match.workspace = "w[tv1]"
        match.float = false
      elseif spec.kind == "maximized" then
        match.fullscreen_state_internal = "1"
      end
      window_rules[name] = hl.window_rule({
        name = name,
        match = match,
        rounding = spec.rounding,
        rounding_power = spec.power,
      })
    end
    window_rules[name]:set_enabled(true)
  end
  for name, rule in pairs(window_rules) do
    if not wanted_names[name] then rule:set_enabled(false) end
  end
end

local function restore()
  lone_window_rule:set_enabled(false)
  if watchdog then watchdog:set_enabled(false) end
  if saved == nil then return end
  use_window_rules({})
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
-- going missing restores too.
local function check_frame()
  if frame_mapped() then
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

--- Shapes windows to the frame: `corner` and `radius` give the corner, `border_size` and the two colours the window
--- borders. Saves the owner's values first, and keeps them until `clear`. A style with no border (width 0, or "" for
--- an invisible colour) leaves the owner's own border size and colour in place instead of drawing an invisible one.
--- @param corner string round, chamfer, pixel or square
--- @param radius number
--- @param border_size number
--- @param active string a colour Hyprland parses, e.g. "rgba(33ccffee)"
--- @param inactive string
local function set(corner, radius, border_size, active, inactive)
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
  local flush_rounding = window_rounding(corner, tonumber(radius) or 0, 0)
  -- A chamfered window's own rounding comes from its rule, so the global one only matters for windows the rule misses.
  -- Power 2 keeps a squircle rounding of the owner's from drawing a round window's arc off the frame's circle.
  local width = tonumber(border_size)
  hl.config({
    decoration = { rounding = chamfered and 0 or rounding, rounding_power = 2 },
    general = {
      border_size = (width and width > 0) and width or saved.border_size,
      col = {
        active_border = (active and active ~= "") and active or saved.active_border,
        inactive_border = (inactive and inactive ~= "") and inactive or saved.inactive_border,
      },
    },
  })
  local power = chamfered and 1 or 2
  local rules = {}
  if chamfered then table.insert(rules, { rounding = rounding, power = 1, kind = "gapped" }) end
  if flush_rounding ~= rounding then
    table.insert(rules, { rounding = flush_rounding, power = power, kind = "lone" })
    table.insert(rules, { rounding = flush_rounding, power = power, kind = "maximized" })
  end
  use_window_rules(rules)
  lone_window_rule:set_enabled(true)
  missed_checks = 0
  if watchdog then
    watchdog:set_enabled(true)
  else
    watchdog = hl.timer(check_frame, { timeout = WATCHDOG_MS, type = "repeat" })
  end
end

-- Global functions which are accessible externally via `hyprctl dispatch "ScreenFrame"`
_G.ScreenFrame = {
  set = function(corner, radius, border_size, active, inactive)
    set(corner, radius, border_size, active, inactive)

    return hl.dsp.no_op()
  end,
  clear = function()
    restore()

    return hl.dsp.no_op()
  end,
}
