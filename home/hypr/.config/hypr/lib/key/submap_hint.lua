--- The compact hint bar a submap shows in place of HyprVim's which-key popup (`hint` on Submap.define).
--- The groups name actions, and the keys and labels come from the submap's own bind rows, so the bar cannot list a key
--- the submap does not have. Quickshell draws it (features/submap_hints/) and shows the hint whose name matches the
--- current submap; this module sends it the hint on every entry.
local Act = require("lib.act") ---@class ActionLib
local Json = require("lib.json") ---@class Json

--- @class SubmapHintItem
--- @field [integer] string  Action ids whose rows the item lists
--- @field args?  table      Only rows whose action args equal these, position by position
--- @field mods?  string     Only rows with exactly these modifiers, e.g. "" or "CTRL"
--- @field label? string     Replaces the whole label taken from the rows, so the rows merge into one entry per modifier set
--- @field tiers? string     Sums up the speed tiers the item leaves out as one entry, e.g. "speed" gives "S/C speed"

--- A group is { heading, item, item... }; an item is an action id or a SubmapHintItem.
--- @alias SubmapHintGroup table

--- @class SubmapHint
local SubmapHint = {
  --- The encoded hint per submap name, built at setup.
  --- @type table<string, string>
  encoded = {},
  --- Why each hint that failed to build was dropped; the submap_hints test fails on any.
  --- @type string[]
  errors = {},
}

-- stylua: ignore
local CAPS = {
  SPACE = "space", RETURN = "Enter", ESCAPE = "Esc", TAB = "Tab", BACKSPACE = "Backspace",
  BRACKETLEFT = "[", BRACKETRIGHT = "]", MINUS = "-", EQUAL = "=", SEMICOLON = ";", APOSTROPHE = "'",
  COMMA = ",", PERIOD = ".", SLASH = "/", GRAVE = "`", BACKSLASH = "\\",
  LEFT = "←", DOWN = "↓", UP = "↑", RIGHT = "→",
}

-- What Shift turns a key into, so SHIFT + SLASH reads as the `?` it types; a key not here gets an `S-` prefix.
-- stylua: ignore
local SHIFTED = {
  SLASH = "?", SEMICOLON = ":", APOSTROPHE = '"', COMMA = "<", PERIOD = ">", EQUAL = "+", MINUS = "_",
  BRACKETLEFT = "{", BRACKETRIGHT = "}", GRAVE = "~", BACKSLASH = "|",
}

local MOD_PREFIX = { CTRL = "C-", ALT = "A-", SUPER = "M-" }
local MOD_ORDER = { "CTRL", "ALT", "SUPER", "SHIFT" }

--- A key string as its modifiers (set and canonical text) and its base key: "CTRL + SHIFT + H" -> {CTRL,SHIFT}, "H".
--- @param key string
--- @return table<string, boolean> mods, string mods_text, string base
local function split_key(key)
  local parts = {}
  for part in (key .. " + "):gmatch("(.-)%s*%+%s+") do
    if part ~= "" then parts[#parts + 1] = part end
  end
  local base = table.remove(parts) or key
  local mods = {}
  for _, mod in ipairs(parts) do
    mods[mod:upper()] = true
  end
  local ordered = {}
  for _, mod in ipairs(MOD_ORDER) do
    if mods[mod] then ordered[#ordered + 1] = mod end
  end
  return mods, table.concat(ordered, " + "), base
end

--- How one base key reads with or without Shift; the second result is false when Shift still needs an `S-`.
--- @param base string
--- @param shift boolean
--- @return string cap, boolean shift_shown
local function base_cap(base, shift)
  local upper = base:upper()
  if #base == 1 and base:match("%a") then return shift and upper or base:lower(), true end
  if shift and SHIFTED[upper] then return SHIFTED[upper], true end
  return CAPS[upper] or base, false
end

--- Collapse base caps into one: a digit run as "1..n" (0 after 9), a direction set run together ("hjkl"; two as
--- "hjkl/aswd"), single symbols run together ("[]"), anything else joined by "/" ("u/d", "space/r/m").
--- @param caps string[]
--- @return string
local function collapse(caps)
  local joined = table.concat(caps)
  if #caps > 1 and ("1234567890"):sub(1, #caps) == joined then return "1.." .. caps[#caps] end
  local letters = false
  for _, cap in ipairs(caps) do
    if utf8.len(cap) ~= 1 then return table.concat(caps, "/") end
    letters = letters or cap:match("%a") ~= nil
  end
  if letters and #caps % 4 ~= 0 then return table.concat(caps, "/") end
  if #caps <= 4 then return joined end
  local sets = {}
  for first = 1, #caps, 4 do
    sets[#sets + 1] = table.concat(caps, "", first, first + 3)
  end
  return table.concat(sets, "/")
end

--- The cap for several rows sharing one modifier set.
--- @param mods table<string, boolean>
--- @param bases string[]
--- @return string
local function entry_cap(mods, bases)
  local caps, shift_shown = {}, true
  for _, base in ipairs(bases) do
    local cap, shown = base_cap(base, mods.SHIFT == true)
    caps[#caps + 1] = cap
    shift_shown = shift_shown and shown
  end
  local prefix = ""
  for _, mod in ipairs(MOD_ORDER) do
    if mods[mod] then
      if mod ~= "SHIFT" then
        prefix = prefix .. MOD_PREFIX[mod]
      elseif not shift_shown then
        prefix = prefix .. "S-"
      end
    end
  end
  return prefix .. collapse(caps)
end

--- A row's label split into the part its siblings share and its tier: "Resize Left (Fast)" -> "Resize", "Fast".
--- Direction words and trailing numbers go, as the collapsed cap already says them.
--- @param desc string
--- @return string stem, string|nil suffix
local function split_desc(desc)
  local stem = desc:gsub("^%+", "")
  local suffix = stem:match("%s*%((.-)%)$")
  stem = stem:gsub("%s*%(.-%)$", "")
  stem = stem:gsub("%s+%d+$", "")
  for _, dir in ipairs({ "Up%-Left", "Up%-Right", "Down%-Left", "Down%-Right", "Left", "Down", "Up", "Right" }) do
    stem = stem:gsub("%s+" .. dir .. "$", "")
  end
  return stem, suffix
end

--- The id and args a raw row names, or nil for a row that runs a function or a dispatcher.
--- @param action any
--- @return string|nil id, table args
local function action_of(action)
  if type(action) == "string" then return action, {} end
  if type(action) == "table" and type(action[1]) == "string" then return action[1], action[2] or {} end
  return nil, {}
end

--- @param item SubmapHintItem
--- @param id string
--- @param args table
--- @param mods_text string
--- @return boolean
local function item_matches(item, id, args, mods_text)
  local named = false
  for _, wanted in ipairs(item) do
    named = named or wanted == id
  end
  if not named then return false end
  if item.mods ~= nil and select(2, split_key(item.mods .. " + X")) ~= mods_text then return false end
  for index, value in pairs(item.args or {}) do
    if args[index] ~= value then return false end
  end
  return true
end

--- The [cap, label] entries one item lists, in bind order. Rows with `desc = false` are hidden twins (the arrow keys
--- beside hjkl) and stay out, as do chords ("H+K", Direction.omni), which no short cap can say.
--- @param item SubmapHintItem
--- @param rows table[]
--- @return table[]
local function item_entries(item, rows)
  local entries, by_key = {}, {}
  local stems_plain = {}
  for _, row in ipairs(rows) do
    local id, args = action_of(row[2])
    local key = type(row[1]) == "table" and row[1][1] or row[1]
    local desc = row[3]
    if id and desc ~= false then
      local mods, mods_text, base = split_key(key)
      if not base:match(".%+.") and item_matches(item, id, args, mods_text) then
        if desc == nil then desc = select(2, Act.row_action(row[2])) or id end
        local stem, suffix = split_desc(desc)
        if item.label then stem = item.label end
        local group_key = mods_text .. "\0" .. stem .. "\0" .. (suffix or "")
        local entry = by_key[group_key]
        if not entry then
          entry = { mods = mods, bases = {}, stem = stem, suffix = suffix }
          by_key[group_key] = entry
          entries[#entries + 1] = entry
        end
        entry.bases[#entry.bases + 1] = base
        if not suffix then stems_plain[stem] = true end
      end
    end
  end

  local out, tier_mods = {}, {}
  for _, entry in ipairs(entries) do
    -- A tier beside its plain sibling ("SHIFT + H" Resize Left (Fast) beside "H" Resize Left) is a speed step: one
    -- entry per tier crowded a narrow screen out, so they are left to the full list, or summed up by `tiers`.
    local is_tier = entry.suffix ~= nil and stems_plain[entry.stem]
    if is_tier then
      for mod in pairs(entry.mods) do
        tier_mods[mod] = true
      end
    else
      local label = entry.stem
      if entry.suffix and not item.label then label = entry.stem .. " (" .. entry.suffix .. ")" end
      out[#out + 1] = { entry_cap(entry.mods, entry.bases), label }
    end
  end

  if item.tiers and next(tier_mods) then
    local letters = {}
    for _, mod in ipairs({ "SHIFT", "CTRL", "ALT" }) do
      if tier_mods[mod] then letters[#letters + 1] = mod:sub(1, 1) end
    end
    out[#out + 1] = { table.concat(letters, "/"), item.tiers }
  end
  return out
end

--- Build the hint Quickshell draws: { name, groups = { { name, keys = { {cap, label}... } }... }, footer = { {cap, label}... },
--- targets? }, `targets` set for a submap with Submap.define `targets`, whose bar numbers the selected windows.
--- An item that matches no row raises, so a hint cannot outlive the bind it names.
--- @param name string    Submap name
--- @param hint SubmapHintGroup[]
--- @param rows table[]   The submap's bind rows as written (action ids, not yet resolved)
--- @param extras { escape: boolean, whichkey: boolean, targets?: boolean }  Which of the binds Submap.define adds itself this submap has, and its `targets`
--- @return table
function SubmapHint.build(name, hint, rows, extras)
  local groups = Json.array()
  for _, group in ipairs(hint) do
    local keys = Json.array()
    for index = 2, #group do
      local item = group[index]
      if type(item) == "string" then item = { item } end
      local entries = item_entries(item, rows)
      if #entries == 0 then
        error("Submap '" .. name .. "' hint '" .. group[1] .. "': no bind row matches " .. table.concat(item, ", "), 0)
      end
      for _, entry in ipairs(entries) do
        keys[#keys + 1] = entry
      end
    end
    groups[#groups + 1] = { name = group[1], keys = keys }
  end

  -- Kept out of the groups: the bar sets these under the submap name, where they cost no column.
  local footer = Json.array()
  if extras.escape then footer[#footer + 1] = { "Esc", "Exit" } end
  if extras.whichkey then footer[#footer + 1] = { "?", "All keys" } end

  return { name = name, groups = groups, footer = footer, targets = extras.targets or nil }
end

--- Build and keep the hint for a submap; Submap.define calls this from setup. A hint that fails to build is reported
--- and dropped rather than raised: raising here would leave the whole submap unbound, and without a hint the submap
--- falls back to the which-key popup.
--- @param name string
--- @param hint SubmapHintGroup[]
--- @param rows table[]
--- @param extras { escape: boolean, whichkey: boolean, targets?: boolean }
function SubmapHint.register(name, hint, rows, extras)
  local ok, built = pcall(SubmapHint.build, name, hint, rows, extras)
  if ok then
    SubmapHint.encoded[name] = Json.encode(built)
    return
  end
  SubmapHint.encoded[name] = nil
  SubmapHint.errors[#SubmapHint.errors + 1] = tostring(built)
  hl.notification.create({ text = tostring(built), timeout = 20000 })
end

--- Send a submap's hint to the bar. Sent on every entry rather than once, so a restarted bar or a reloaded config
--- has the current one; the bar keeps each by name and shows it from the submap event without waiting for this.
--- @param name string
function SubmapHint.send(name)
  local encoded = SubmapHint.encoded[name]
  if encoded then Act.Ipc("submap_hints", "set", encoded)() end
end

--- Drop every hint the bar holds, and the selection. Called once per config load: a hint a reload removed or dropped is
--- never sent again, so without this the bar would keep showing the old one. It carries the load's selection
--- generation, so a selection the old config sent that lands after it is ignored.
function SubmapHint.clear_bar() Act.Ipc("submap_hints", "clear", tostring(require("lib.selection").generation()))() end

--- `names` plus every submap with a hint: HyprVim's `which_key.auto_show.disabled`, since the hint bar replaces the
--- which-key popup there. HyprVim reads that list once at setup, so a hint defined later (from custom/) still gets the
--- popup as well.
--- @param names string[]
--- @return string[]
function SubmapHint.without_whichkey(names)
  local out = {}
  for _, name in ipairs(names) do
    out[#out + 1] = name
  end
  local hinted = {}
  for name in pairs(SubmapHint.encoded) do
    hinted[#hinted + 1] = name
  end
  table.sort(hinted)
  for _, name in ipairs(hinted) do
    out[#out + 1] = name
  end
  return out
end

return SubmapHint
