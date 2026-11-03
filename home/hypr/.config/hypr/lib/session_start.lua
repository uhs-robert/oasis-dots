-- `hyprland.start` fires once per Hyprland process and reaches only the config loaded at that moment. After a crash,
-- start-hyprland relaunches Hyprland in safe mode with a recovery config, and the dialog's "Load config" brings this
-- config in by a reload, after start has fired. A marker in the instance's runtime dir tells that late first load
-- apart from an ordinary reload, which must not run the session hooks again.

local SessionStart = {}
local hooks = {}

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

--- Queues `fn` to run once per Hyprland process. Nothing runs unless `arm` is reached.
--- @param fn fun()
--- @return nil
function SessionStart.on(fn) table.insert(hooks, fn) end

--- Registers the queued hooks; call it as the config's last line. A config that raises before this line registers
--- nothing and leaves no marker, so the repaired reload still runs every hook.
--- @return nil
function SessionStart.arm()
  if marked() then return end
  -- Monitors exist only once the backend has started, so on the first launch's parse this is empty and start is still due.
  local event = #hl.get_monitors() > 0 and "config.reloaded" or "hyprland.start"
  hl.on(event, function()
    mark()
    -- As separate handlers they failed alone, so one hook that raises must not skip the rest.
    for _, fn in ipairs(hooks) do
      local ok, err = pcall(fn)
      if not ok then print("session_start: hook failed: " .. tostring(err)) end
    end
  end)
end

return SessionStart
