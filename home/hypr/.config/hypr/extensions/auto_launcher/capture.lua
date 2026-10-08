-- home/hypr/.config/hypr/extensions/auto_launcher/capture.lua
-- Turns open windows into draft session entries for the Settings Sessions tab. Settings runs
--   hyprctl eval "require('extensions.auto_launcher.capture').draft({'0x...'}, '<runtime path>.json')"
-- and reads `{ "windows": [ <AppEntry as JSON> ] }` back from the file, since eval prints nothing.

local Config = require("config") ---@class Config
local Json = require("lib.json") ---@class Json
local Provenance = require("extensions.auto_launcher.provenance") ---@class Provenance

local SPECIAL_PREFIX = "special:"

--- A window reduced to the plain fields capture reads.
--- @class CaptureWindow
--- @field address string
--- @field class string
--- @field title string
--- @field pid integer
--- @field floating boolean
--- @field at { x: number, y: number }
--- @field size { x: number, y: number }
--- @field workspace_id integer
--- @field workspace_name string

--- @class Capture
local Capture = {}

--- @param value number
--- @return integer
local function round(value) return math.floor(value + 0.5) end

--- Quotes an argument for sh only when it holds characters the shell would treat specially.
--- @param arg string
--- @return string
local function shell_quote(arg)
  if arg:match("^[%w%-_./:=+,@%%]+$") then return arg end
  return "'" .. arg:gsub("'", "'\\''") .. "'"
end

--- Reconstructs a command line from /proc/<pid>/cmdline; nil when the process is gone or has no arguments.
--- @param pid integer
--- @return string|nil
function Capture.proc_cmd(pid)
  local file = io.open("/proc/" .. pid .. "/cmdline", "rb")
  if not file then return nil end
  local raw = file:read("a")
  file:close()
  local args = {}
  for arg in raw:gmatch("[^\0]+") do
    args[#args + 1] = shell_quote(arg)
  end
  if #args == 0 then return nil end
  return table.concat(args, " ")
end

--- Command and window match for one window: the launching entry's exactly when known, else guessed from /proc.
--- @param w CaptureWindow
--- @param launched AppEntry|nil
--- @param proc_cmd fun(pid: integer): string|nil
--- @return AppEntry|nil
local function identity(w, launched, proc_cmd)
  if launched then
    local entry = { cmd = launched.cmd, delay = launched.delay, class = launched.class, title = launched.title }
    if not (entry.class or entry.title) then
      entry.class, entry.title = w.class ~= "" and w.class or nil, w.class == "" and w.title or nil
    end
    return entry
  end
  local cmd = proc_cmd(w.pid)
  if not cmd then return nil end
  return {
    cmd = cmd,
    class = w.class ~= "" and w.class or nil,
    title = w.class == "" and w.title or nil,
    guessed = true,
  }
end

--- Placement fields from the inverse of the launcher's `ws()`: slot and offset from the workspace id.
--- @param w CaptureWindow
--- @param workspaces_per_monitor integer
--- @return { monitor: integer, ws: integer }|{ special: string }|nil nil for a named non-special workspace
local function placement(w, workspaces_per_monitor)
  if w.workspace_name:sub(1, #SPECIAL_PREFIX) == SPECIAL_PREFIX then
    return { special = w.workspace_name:sub(#SPECIAL_PREFIX + 1) }
  end
  if w.workspace_id < 1 then return nil end
  return {
    monitor = (w.workspace_id - 1) // workspaces_per_monitor + 1,
    ws = (w.workspace_id - 1) % workspaces_per_monitor + 1,
  }
end

--- Sort key putting numbered workspaces first by id, then special ones by name.
--- @param place table
--- @param w CaptureWindow
--- @return number, string
local function group_key(place, w)
  if place.special then return math.huge, place.special end
  return w.workspace_id, ""
end

--- Builds the draft entries, grouped by workspace; within one, tiled windows run left to right, top to bottom,
--- then floating ones.
--- A tiled window only records a size when another captured tiled window shares its workspace.
--- @param windows CaptureWindow[]
--- @param launched table<string, AppEntry> provenance, keyed by address
--- @param proc_cmd fun(pid: integer): string|nil
--- @param workspaces_per_monitor integer
--- @return AppEntry[]
function Capture.build(windows, launched, proc_cmd, workspaces_per_monitor)
  local items = {}
  local tiled_per_group = {}
  for _, w in ipairs(windows) do
    local place = placement(w, workspaces_per_monitor)
    local entry = place and identity(w, launched[w.address], proc_cmd)
    if entry then
      for field, value in pairs(place) do
        entry[field] = value
      end
      local group, name = group_key(place, w)
      items[#items + 1] = { entry = entry, window = w, group = group, name = name }
      if not w.floating then
        local key = group .. name
        tiled_per_group[key] = (tiled_per_group[key] or 0) + 1
      end
    end
  end

  table.sort(items, function(a, b)
    if a.group ~= b.group then return a.group < b.group end
    if a.name ~= b.name then return a.name < b.name end
    if a.window.floating ~= b.window.floating then return not a.window.floating end
    if a.window.at.x ~= b.window.at.x then return a.window.at.x < b.window.at.x end
    if a.window.at.y ~= b.window.at.y then return a.window.at.y < b.window.at.y end
    return a.window.address < b.window.address
  end)

  local entries = {}
  for _, item in ipairs(items) do
    local w, entry = item.window, item.entry
    if w.floating then
      entry.float = true
      entry.size = { round(w.size.x), round(w.size.y) }
      entry.pos = { round(w.at.x), round(w.at.y) }
    elseif tiled_per_group[item.group .. item.name] > 1 then
      entry.size = { round(w.size.x), round(w.size.y) }
    end
    entries[#entries + 1] = entry
  end
  return entries
end

--- Writes draft entries for the windows at `addresses` to `out_path`.
--- @param addresses string[]
--- @param out_path string
function Capture.draft(addresses, out_path)
  local wanted = {}
  for _, address in ipairs(addresses) do
    wanted[address] = true
  end

  local windows = {}
  for _, w in ipairs(hl.get_windows() or {}) do
    if wanted[w.address] and w.workspace then
      windows[#windows + 1] = {
        address = w.address,
        class = w.class or "",
        title = w.title or "",
        pid = w.pid,
        floating = w.floating,
        at = { x = w.at.x, y = w.at.y },
        size = { x = w.size.x, y = w.size.y },
        workspace_id = w.workspace.id,
        workspace_name = w.workspace.name,
      }
    end
  end

  local entries = Capture.build(windows, Provenance.load(), Capture.proc_cmd, Config.ws_per_monitor)
  local file = assert(io.open(out_path, "w"))
  file:write(Json.encode({ windows = Json.array(entries) }))
  file:close()
end

return Capture
