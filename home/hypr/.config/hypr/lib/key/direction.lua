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
  { mod = "",             amount = 10,  suffix = "" },
  { mod = "SHIFT",        amount = 100, suffix = " (Fast)" },
  { mod = "CTRL",         amount = 1,   suffix = " (Pixel)" },
  { mod = "CTRL + SHIFT", amount = 300, suffix = " (Ultra Fast)" },
}

--- Build bind rows for a single DirActions set.
--- @param actions     DirActions
--- @param desc_prefix string
--- @param mod         string|nil  Optional modifier prefix, e.g. "SHIFT"
--- @param opts        table|nil   Per-row opts merged into each row's [4]
--- @return table[]
function Direction.binds(actions, desc_prefix, mod, opts)
  local p = (mod and mod ~= "") and (mod .. " + ") or ""

  return {
    { { p .. "H", p .. "LEFT"  }, actions.left,  desc_prefix .. " Left",  opts },
    { { p .. "J", p .. "DOWN"  }, actions.down,  desc_prefix .. " Down",  opts },
    { { p .. "K", p .. "UP"    }, actions.up,    desc_prefix .. " Up",    opts },
    { { p .. "L", p .. "RIGHT" }, actions.right, desc_prefix .. " Right", opts },
  }
end

--- Build bind rows for all speed tiers using an at(amount) factory.
--- `at_fn` must satisfy: (number) -> DirActions.
--- @param at_fn       fun(amount: number): DirActions
--- @param desc_prefix string
--- @param tiers       SpeedTier[]|nil  Defaults to Direction.tiers
--- @return table[]
function Direction.speed_binds(at_fn, desc_prefix, tiers)
  tiers = tiers or Direction.tiers

  local rows = {}

  for _, tier in ipairs(tiers) do
    for _, row in ipairs(Direction.binds(at_fn(tier.amount), desc_prefix, tier.mod, { repeating = true })) do
      row[3] = row[3] .. tier.suffix
      table.insert(rows, row)
    end
  end

  return rows
end

return Direction
