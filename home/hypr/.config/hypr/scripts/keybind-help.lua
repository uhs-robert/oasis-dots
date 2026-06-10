#!/usr/bin/env lua
-- home/hypr/.config/hypr/scripts/keybind-help.lua
--
-- Shows keybinds for the active Hyprland submap in rofi and dispatches the selection.
-- Binds without a description are excluded. submap_universal binds always appear.

--- Modifier bitmask -> display name, evaluated highest bit first.
--- @type { mask: integer, name: string }[]
local MOD_BITS = {
  { mask = 64, name = "SUPER" },
  { mask = 8, name = "ALT" },
  { mask = 4, name = "CTRL" },
  { mask = 1, name = "SHIFT" },
}

--- Read a $theme_<name> variable from theme.conf and return it as a "#RRGGBB" hex string.
--- @param name string
--- @return string
local function get_theme_color(name)
  local theme_conf = (os.getenv("HOME") or "") .. "/.config/hypr/theme.conf"
  local h = io.popen("grep '^\\$theme_" .. name .. " ' " .. theme_conf)
  local line = h and h:read("l")
  if h then h:close() end
  local hex = line and line:match("rgb%((%x+)%)")
  return hex and ("#" .. hex) or "#ffffff"
end

--- Convert a Hyprland modmask integer to a "SUPER+CTRL" style string.
--- @param mask integer
--- @return string
local function modmask_to_str(mask)
  local parts = {}
  for _, m in ipairs(MOD_BITS) do
    if mask & m.mask ~= 0 then table.insert(parts, m.name) end
  end
  return table.concat(parts, "+")
end

--- Read the active Hyprland submap by writing it to a tmpfile via hyprctl eval.
--- Returns "" when in the root submap.
--- @return string
local function get_active_submap()
  local submap_file = "/tmp/keybind-help-submap-" .. os.time()
  os.execute(
    string.format(
      'hyprctl eval \'local f = io.open("%s", "w"); f:write(hl.get_current_submap()); f:close()\'',
      submap_file
    )
  )
  local sf = io.open(submap_file, "r")
  local submap = sf and sf:read("l") or ""
  if sf then sf:close() end
  os.remove(submap_file)
  return submap
end

--- Fetch all binds with descriptions from Hyprland, filtered to the active submap.
--- submap_universal binds are always included regardless of active submap.
--- @param active_submap string
--- @return { arg: string, chord: string, desc: string }[]
local function get_binds(active_submap)
  local h = io.popen([[
    hyprctl binds -j | jq -r '
      .[] | select(.has_description == true) |
      [.arg, (.modmask | tostring), .key, .submap, .submap_universal, .description] | @tsv
    '
  ]])
  if not h then return {} end

  local binds = {}
  for line in h:lines() do
    local arg, mask_s, key, submap, universal, desc =
      line:match("^([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]*)\t([^\t]*)\t(.+)$")
    if arg and (submap == active_submap or universal == "true") then
      local mods = modmask_to_str(tonumber(mask_s) or 0)
      local chord = mods ~= "" and (mods .. "+" .. key) or key
      table.insert(binds, { arg = arg, chord = chord, desc = desc })
    end
  end
  h:close()

  table.sort(binds, function(a, b) return a.desc < b.desc end)
  return binds
end

--- Escape special Pango markup characters in a string.
--- @param s string
--- @return string
local function pango_escape(s) return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")) end

--- Show binds in rofi and return the selected index (0-based), or nil if cancelled.
--- @param binds { arg: string, chord: string, desc: string }[]
--- @param prompt string
--- @return integer|nil
local function rofi_select(binds, prompt)
  local accent = get_theme_color("accent")
  local secondary = get_theme_color("secondary")

  local max_chord = 0
  for _, b in ipairs(binds) do
    max_chord = math.max(max_chord, #b.chord)
  end

  local labels = {}
  for _, b in ipairs(binds) do
    local chord = string.format('<span foreground="%s">%s</span>', secondary, pango_escape(b.chord))
      .. string.rep(" ", max_chord - #b.chord + 4)
    local desc = pango_escape(b.desc)
    if b.desc:sub(1, 1) == "+" then desc = string.format('<span foreground="%s">%s</span>', accent, desc) end
    table.insert(labels, chord .. desc)
  end

  local tmpfile = "/tmp/keybind-help-" .. os.time()
  local f = assert(io.open(tmpfile, "w"))
  f:write(table.concat(labels, "\n"))
  f:close()

  local rofi = io.popen("rofi -dmenu -i -markup-rows -p " .. string.format("%q", prompt) .. " -format i < " .. tmpfile)
  local idx_str = rofi and rofi:read("l")
  if rofi then rofi:close() end
  os.remove(tmpfile)

  return tonumber(idx_str)
end

--- Entry point. Reads active submap, shows filtered binds in rofi, dispatches selection.
local run = function()
  local active_submap = get_active_submap()
  local binds = get_binds(active_submap)
  local prompt = active_submap ~= "" and ("Keybinds [" .. active_submap .. "]") or "Keybinds"
  local idx = rofi_select(binds, prompt)

  if not idx then os.exit(0) end

  local selected = binds[idx + 1]
  if selected then os.execute("hyprctl eval 'debug.getregistry()[" .. selected.arg .. "]()'") end
end

run()
