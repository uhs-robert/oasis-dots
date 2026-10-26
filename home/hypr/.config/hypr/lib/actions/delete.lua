--- Close actions for the Delete submap: every window on the workspace, or every window of one kind of app.

local Closed = require("lib.closed_windows") --- @class ClosedWindows

-- stylua: ignore start
--- App classes per group (case-insensitive substring match).
local CLASSES = {
  browsers  = { "firefox", "qutebrowser", "chromium", "brave-browser", "vivaldi", "opera", "chrome" },
  mail      = { "betterbird", "thunderbird" },
  chat      = { "slack", "discord", "telegram-desktop", "signal" },
  terminals = { "foot", "kitty", "ghostty", "alacritty", "wezterm", "xterm", "konsole" },
  editors   = { "nvim", "neovim", "code", "codium", "vscodium", "gedit", "kate", "emacs" },
  files     = { "thunar", "nautilus", "nemo", "dolphin", "pcmanfm" },
  games     = { "steam", "lutris", "heroic", "bottles", "gamescope" },
  media     = { "mpv", "vlc", "celluloid", "totem", "rhythmbox", "spotify" },
}
-- stylua: ignore end

--- @class DeleteActions
local Delete = {}

--- The group names `close_class` takes, sorted.
--- @type string[]
Delete.groups = {}
for name in pairs(CLASSES) do
  Delete.groups[#Delete.groups + 1] = name
end
table.sort(Delete.groups)

--- Close or kill every window on the active workspace.
--- @param kill boolean  true -> SIGKILL via pid, false -> graceful close
--- @param except_active boolean|nil  when true, skip the currently focused window
--- @return fun()
function Delete.close_workspace(kill, except_active)
  return function()
    local ws = hl.get_active_workspace()
    if not ws then return end
    local active_addr = except_active and (hl.get_active_window() or {}).address
    local targets = {}
    for _, w in ipairs(hl.get_windows() or {}) do
      if w.workspace and w.workspace.id == ws.id and w.address ~= active_addr then targets[#targets + 1] = w end
    end
    Closed.close(targets, kill and "sigkill" or "close")
  end
end

--- Close or kill windows whose class matches any entry of a group.
--- @param group string  Key into CLASSES
--- @param kill boolean|nil  true -> SIGKILL via pid, false -> graceful close
--- @return fun()
function Delete.close_class(group, kill)
  local classes = assert(CLASSES[group], "unknown window group: " .. tostring(group))
  return function()
    local targets = {}
    for _, w in ipairs(hl.get_windows() or {}) do
      local lower = w.class:lower()
      for _, c in ipairs(classes) do
        if lower:find(c, 1, true) then
          targets[#targets + 1] = w
          break
        end
      end
    end
    Closed.close(targets, kill and "sigkill" or "close")
  end
end

return Delete
