--- Directional bind helpers for H/J/K/L + arrow key patterns.
--- Supports single-tier binds from a DirActions set, or multi-tier
--- speed binds from an at(amount) factory.

--- @class Direction
local Direction = {}

--- @class SpeedTier
--- @field mod    string  Modifier prefix, e.g. "SHIFT" or "CTRL + SHIFT". Empty string for no modifier.
--- @field amount number  Pixel step size for this tier
--- @field suffix string  Description suffix, e.g. " (Fast)"

--- Default speed tiers. Override per-call via the tiers parameter.
--- @type SpeedTier[]
Direction.tiers = {
  { mod = "", amount = 10, suffix = "" },
  { mod = "SHIFT", amount = 100, suffix = " (Fast)" },
  { mod = "CTRL", amount = 1, suffix = " (Pixel)" },
  { mod = "CTRL + SHIFT", amount = 300, suffix = " (Ultra Fast)" },
}

--- Build bind rows for a single DirActions set.
--- @param actions     DirActions
--- @param desc_prefix string
--- @param mod         string|nil          Optional modifier prefix, e.g. "SHIFT"
--- @param opts        HL.BindOptions|nil  Per-row opts merged into each row's [4]
--- @param desc_suffix string|nil          Optional suffix appended to each description
--- @return table[]
function Direction.binds(actions, desc_prefix, mod, opts, desc_suffix)
  local p = (mod and mod ~= "") and (mod .. " + ") or ""
  local s = desc_suffix or ""

  local function row(letter, arrow, action, dir)
    return { { p .. letter, p .. arrow }, action, desc_prefix .. " " .. dir .. s, opts }
  end

  return {
    row("H", "LEFT", actions.left, "Left"),
    row("J", "DOWN", actions.down, "Down"),
    row("K", "UP", actions.up, "Up"),
    row("L", "RIGHT", actions.right, "Right"),
  }
end

--- Build bind rows for all speed tiers using an at(amount) factory.
--- `fn` receives an amount and returns a DirActions.
--- @param fn          fun(amount: number): DirActions
--- @param desc_prefix string
--- @param tiers       SpeedTier[]|nil  Defaults to Direction.tiers
--- @return table[]
function Direction.speed_binds(fn, desc_prefix, tiers)
  tiers = tiers or Direction.tiers

  local rows = {}

  for _, tier in ipairs(tiers) do
    local tier_rows = Direction.binds(fn(tier.amount), desc_prefix, tier.mod, { repeating = true }, tier.suffix)
    table.move(tier_rows, 1, #tier_rows, #rows + 1, rows)
  end

  return rows
end

--- Build diagonal (omni-direction) bind rows for a single DirActions set.
--- Chords two direction keys (e.g. "H+K") to move both axes at once. Chord
--- order matters ("H+K" fires, "K+H" doesn't), so both orderings are bound.
--- @param actions     DirActions
--- @param desc_prefix string
--- @param mod         string|nil          Optional modifier prefix, e.g. "SHIFT"
--- @param opts        HL.BindOptions|nil  Per-row opts merged into each row's [4]
--- @param desc_suffix string|nil          Optional suffix appended to each description
--- @return table[]
function Direction.omni(actions, desc_prefix, mod, opts, desc_suffix)
  local p = (mod and mod ~= "") and (mod .. " + ") or ""
  local s = desc_suffix or ""

  local function row(k1, k2, action, dir) return { { p .. k1, p .. k2 }, action, desc_prefix .. " " .. dir .. s, opts } end

  return {
    row("H+K", "K+H", actions.nw, "Up-Left"),
    row("L+K", "K+L", actions.ne, "Up-Right"),
    row("H+J", "J+H", actions.sw, "Down-Left"),
    row("L+J", "J+L", actions.se, "Down-Right"),
  }
end

--- Build diagonal bind rows for all speed tiers using an at(amount) factory.
--- `fn` receives an amount and returns a DirActions.
--- @param fn          fun(amount: number): DirActions
--- @param desc_prefix string
--- @param tiers       SpeedTier[]|nil  Defaults to Direction.tiers
--- @return table[]
function Direction.omni_binds(fn, desc_prefix, tiers)
  tiers = tiers or Direction.tiers

  local rows = {}

  for _, tier in ipairs(tiers) do
    local tier_rows = Direction.omni(fn(tier.amount), desc_prefix, tier.mod, { repeating = true }, tier.suffix)
    table.move(tier_rows, 1, #tier_rows, #rows + 1, rows)
  end

  return rows
end

return Direction
