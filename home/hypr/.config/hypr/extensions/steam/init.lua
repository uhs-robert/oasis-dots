-- home/hypr/.config/hypr/extensions/steam/init.lua
-- Regenerates a prime-run-wrapped Steam desktop entry on hybrid GPU machines so
-- launching Steam from rofi drun runs it on the dGPU, same as the other launch points.

local SOURCE = "/usr/share/applications/steam.desktop"
local MARKER = "X-Hypr-Generated=true"

local M = {}

--- @param path string
--- @return string|nil
local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  return content
end

--- @param path string
--- @return boolean
local function is_generated(path)
  local content = read_file(path)
  return content ~= nil and content:find(MARKER, 1, true) ~= nil
end

--- Rewrites every steam Exec line to go through prime-run and writes it to target.
--- @param content string
--- @param target string
local function write_override(content, target)
  content = content:gsub("Exec=/usr/bin/steam", "Exec=prime-run /usr/bin/steam")
  content = content:gsub("%[Desktop Entry%]\n", "[Desktop Entry]\n" .. MARKER .. "\n", 1)

  local f = io.open(target, "w")
  if not f then return end
  f:write(content)
  f:close()
end

--- Writes or removes the user Steam desktop override to match whether Steam runs via prime-run.
--- Never touches a target file it did not generate.
--- @param use_prime boolean
--- @param apps_dir string|nil override for testing (default: ~/.local/share/applications)
function M.sync(use_prime, apps_dir)
  apps_dir = apps_dir or (os.getenv("HOME") .. "/.local/share/applications")
  local target = apps_dir .. "/steam.desktop"
  local source = use_prime and read_file(SOURCE)

  if source then
    if read_file(target) and not is_generated(target) then return end
    os.execute('mkdir -p "' .. apps_dir .. '"')
    write_override(source, target)
  elseif is_generated(target) then
    os.remove(target)
  end
end

return M
