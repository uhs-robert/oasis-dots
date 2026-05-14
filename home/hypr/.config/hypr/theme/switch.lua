#!/usr/bin/env lua
-- home/hypr/.config/hypr/theme/switch.lua
-- Standalone theme switcher. No hl dependency, safe to spawn as a subprocess.
-- Picks a palette via rofi, saves the choice, then reloads Hyprland so all
-- in-process generators (hyprland, waybar, rofi, conf) run with hl available.

local HOME = os.getenv("HOME")
local COLORS_DIR = HOME .. "/.config/hypr/theme/colors"
local STATE_FILE = HOME .. "/.config/hypr/theme/.current_theme"
local DMENU = arg[1] or "rofi -name rofiDmenu -i -dmenu"

--- Returns sorted list of palette names from the colors directory.
--- @return string[]
local function list_themes()
  local lsh = io.popen("ls " .. COLORS_DIR .. "/*.lua 2>/dev/null")
  if not lsh then return {} end
  local names = {}
  for path in lsh:lines() do
    local name = path:match("([^/]+)%.lua$")
    if name then table.insert(names, name) end
  end
  lsh:close()
  table.sort(names)
  return names
end

--- Shows a rofi dmenu picker and returns the selected theme name, or nil if cancelled.
--- @param names string[]
--- @return string|nil
local function pick_theme(names)
  local pick = io.popen(string.format('echo "%s" | %s -p "Theme"', table.concat(names, "\n"), DMENU))
  if not pick then return nil end
  local choice = pick:read("*line")
  pick:close()
  return (choice and choice ~= "") and choice or nil
end

--- Persists the chosen theme name to the state file.
--- @param name string
local function save(name)
  local f = assert(io.open(STATE_FILE, "w"))
  f:write(name)
  f:close()
end

--- Reloads Hyprland then restarts waybar + swaync after a brief delay.
local function apply()
  os.execute("hyprctl reload")
  os.execute(
    "sleep 0.1 && pkill waybar; waybar -c ~/.config/waybar/config.jsonc -s ~/.config/waybar/style.css > /dev/null 2>&1 &"
  )
  os.execute("pkill swaync; swaync &")
end

--- Entry point. Lists themes, prompts user, persists choice, and reloads.
local function init()
  local names = list_themes()
  if #names == 0 then os.exit(1) end

  local choice = pick_theme(names)
  if not choice then os.exit(0) end

  save(choice)
  apply()
end

init()
