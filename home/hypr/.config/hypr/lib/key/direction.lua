--- Directional bind helpers for H/J/K/L + arrow key patterns.
--- Supports single-tier binds from a DirActions set, or multi-tier
--- speed binds from an at(amount) factory.

local Config = require("config")

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

--- @class DirectionKeys
--- @field left   string
--- @field down   string
--- @field up     string
--- @field right  string
--- @field arrows boolean|nil  Also bind the arrow keys (default true); false for a second letter set beside one that already does

--- Letter sets a caller can pass as `key_set`; HJKL is what every call without one uses.
--- @type table<string, DirectionKeys>
Direction.key_sets = {
  hjkl = { left = "H", down = "J", up = "K", right = "L" },
  wasd = { left = "A", down = "S", up = "W", right = "D" },
}

--- Order a letter/arrow key pair by Config.vim_mode.
--- @param letter string
--- @param arrow  string
--- @return string shown, string hidden
function Direction.keys(letter, arrow)
  if Config.vim_mode then return letter, arrow end
  return arrow, letter
end

--- Build bind rows for a single DirActions set.
--- @param actions     DirActions
--- @param desc_prefix string
--- @param mod         string|nil          Optional modifier prefix, e.g. "SHIFT"
--- @param opts        HL.BindOptions|nil  Per-row opts merged into each row's [4]
--- @param desc_suffix string|nil          Optional suffix appended to each description
--- @param key_set     DirectionKeys|nil    Letters to bind (default Direction.key_sets.hjkl)
--- @return table[]
function Direction.binds(actions, desc_prefix, mod, opts, desc_suffix, key_set)
  key_set = key_set or Direction.key_sets.hjkl
  local p = (mod and mod ~= "") and (mod .. " + ") or ""
  local s = desc_suffix or ""

  local rows = {}

  local function add(letter, arrow, action, dir)
    if key_set.arrows == false then
      -- Which-key lists the letter only when letters lead; with vim_mode off the arrows lead and are bound elsewhere.
      local desc = Config.vim_mode and (desc_prefix .. " " .. dir .. s) or nil
      rows[#rows + 1] = { p .. letter, action, desc, opts }
      return
    end

    local shown, hidden = Direction.keys(letter, arrow)

    -- Hidden key omits desc so WhichKey skips it.
    rows[#rows + 1] = { p .. shown, action, desc_prefix .. " " .. dir .. s, opts }
    rows[#rows + 1] = { p .. hidden, action, nil, opts }
  end

  add(key_set.left, "LEFT", actions.left, "Left")
  add(key_set.down, "DOWN", actions.down, "Down")
  add(key_set.up, "UP", actions.up, "Up")
  add(key_set.right, "RIGHT", actions.right, "Right")

  return rows
end

--- Build bind rows for all speed tiers using an at(amount) factory.
--- `fn` receives an amount and returns a DirActions.
--- @param fn          fun(amount: number): DirActions
--- @param desc_prefix string
--- @param tiers       SpeedTier[]|nil  Defaults to Direction.tiers
--- @param key_set     DirectionKeys|nil  Defaults to HJKL
--- @return table[]
function Direction.speed_binds(fn, desc_prefix, tiers, key_set)
  tiers = tiers or Direction.tiers

  local rows = {}

  for _, tier in ipairs(tiers) do
    local tier_rows =
      Direction.binds(fn(tier.amount), desc_prefix, tier.mod, { repeating = true }, tier.suffix, key_set)
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
--- @param key_set     DirectionKeys|nil    Letters to chord (default Direction.key_sets.hjkl)
--- @return table[]
function Direction.omni(actions, desc_prefix, mod, opts, desc_suffix, key_set)
  key_set = key_set or Direction.key_sets.hjkl
  local p = (mod and mod ~= "") and (mod .. " + ") or ""
  local s = desc_suffix or ""

  local function row(a, b, action, dir)
    return { { p .. a .. "+" .. b, p .. b .. "+" .. a }, action, desc_prefix .. " " .. dir .. s, opts }
  end

  return {
    row(key_set.left, key_set.up, actions.nw, "Up-Left"),
    row(key_set.right, key_set.up, actions.ne, "Up-Right"),
    row(key_set.left, key_set.down, actions.sw, "Down-Left"),
    row(key_set.right, key_set.down, actions.se, "Down-Right"),
  }
end

--- Build diagonal bind rows for all speed tiers using an at(amount) factory.
--- `fn` receives an amount and returns a DirActions.
--- @param fn          fun(amount: number): DirActions
--- @param desc_prefix string
--- @param tiers       SpeedTier[]|nil  Defaults to Direction.tiers
--- @param key_set     DirectionKeys|nil  Defaults to HJKL
--- @return table[]
function Direction.omni_binds(fn, desc_prefix, tiers, key_set)
  tiers = tiers or Direction.tiers

  local rows = {}

  for _, tier in ipairs(tiers) do
    local tier_rows = Direction.omni(fn(tier.amount), desc_prefix, tier.mod, { repeating = true }, tier.suffix, key_set)
    table.move(tier_rows, 1, #tier_rows, #rows + 1, rows)
  end

  return rows
end

return Direction
