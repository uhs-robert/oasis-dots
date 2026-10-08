-- home/hypr/.config/hypr/extensions/auto_launcher/provenance.lua
-- Remembers which AppEntry opened each window, so capture can save the exact command instead of guessing from /proc.
-- Lives in $XDG_RUNTIME_DIR/hypr-launched.json as { "<window address>": <AppEntry as JSON> }: it outlives
-- `hyprctl reload` and is cleared at logout, the same lifetime as the addresses it keys.

local Json = require("lib.json") ---@class Json
local Sessions = require("extensions.auto_launcher.sessions") ---@class Sessions

--- @class Provenance
local Provenance = {}

--- @return string
function Provenance.path()
  local runtime = os.getenv("XDG_RUNTIME_DIR")
  return ((runtime and runtime ~= "") and runtime or "/tmp") .. "/hypr-launched.json"
end

--- Address to launching entry; a missing or malformed file reads as empty.
--- @return table<string, AppEntry>
function Provenance.load()
  local file = io.open(Provenance.path(), "r")
  if not file then return {} end
  local text = file:read("a")
  file:close()
  local data = Json.decode(text)
  return type(data) == "table" and data or {}
end

--- Records that `app` opened the window at `address`, dropping entries for windows that have closed.
--- @param address string
--- @param app AppEntry
function Provenance.record(address, app)
  local open = {}
  for _, w in ipairs(hl.get_windows() or {}) do
    open[w.address] = true
  end

  local launched = {}
  for known, entry in pairs(Provenance.load()) do
    if open[known] then launched[known] = entry end
  end
  launched[address] = Sessions.sanitize_entry(app)

  local tmp = Provenance.path() .. ".tmp"
  local file = io.open(tmp, "w")
  if not file then return end
  file:write(Json.encode(launched))
  file:close()
  os.rename(tmp, Provenance.path())
end

return Provenance
