-- `hyprland.start` fires once per Hyprland process and reaches only the config loaded at that moment. After a crash,
-- start-hyprland relaunches Hyprland in safe mode with a recovery config, and the dialog's "Load config" brings this
-- config in by a reload, after start has fired. A marker in the instance's runtime dir tells that late first load
-- apart from an ordinary reload, which must not run the session hooks again.

local function marker_path()
  local runtime_dir = os.getenv("XDG_RUNTIME_DIR")
  if runtime_dir == nil or runtime_dir == "" then runtime_dir = "/tmp" end
  return runtime_dir .. "/hypr/" .. (os.getenv("HYPRLAND_INSTANCE_SIGNATURE") or "") .. "/dotfiles-session-started"
end

local function marked()
  local file = io.open(marker_path(), "r")
  if not file then return false end
  file:close()
  return true
end

local function mark()
  local file = io.open(marker_path(), "w")
  if file then file:close() end
end

-- Monitors exist only once the backend has started, so on the first launch's parse this is empty and start is still due.
local loaded_late = not marked() and #hl.get_monitors() > 0
local event = loaded_late and "config.reloaded" or "hyprland.start"
hl.on(event, mark)

--- Runs `fn` once per Hyprland process: on `hyprland.start`, or right after this load when start already passed.
--- @param fn fun()
--- @return nil
return function(fn) hl.on(event, fn) end
