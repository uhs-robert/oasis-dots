--- Delete submap
--- Destructive window/session actions organized around the verb "destroy/close"

local Config = require("config") --- @class Config
local Submap = require("lib.key.submap") --- @class Submap
local Cmd = require("lib.actions.cmd") ---@class Cmd
local Window = require("lib.actions.window") ---@class WindowActions

-- stylua: ignore start
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

--- Close or kill every window on the active workspace.
--- @param kill boolean  true -> SIGKILL via pid, false -> graceful close
--- @param except_active boolean|nil  when true, skip the currently focused window
--- @return fun()
local function close_workspace_windows(kill, except_active)
  return function()
    local ws = hl.get_active_workspace()
    if not ws then return end
    local active_addr = except_active and (hl.get_active_window() or {}).address
    for _, w in ipairs(hl.get_windows() or {}) do
      if w.workspace and w.workspace.id == ws.id then
        if not active_addr or w.address ~= active_addr then
          if kill then
            os.execute("kill -9 " .. tostring(w.pid))
          else
            hl.dispatch(hl.dsp.window.close({ window = "address:" .. w.address }))
          end
        end
      end
    end
  end
end

--- Close or kill windows whose class matches any entry (case-insensitive substring).
--- @param classes string[]
--- @param kill boolean|nil  true -> SIGKILL via pid, false -> graceful close
--- @return fun()
local function close_by_class(classes, kill)
  return function()
    for _, w in ipairs(hl.get_windows() or {}) do
      local lower = w.class:lower()
      for _, c in ipairs(classes) do
        if lower:find(c, 1, true) then
          if kill then
            os.execute("kill -9 " .. tostring(w.pid))
          else
            hl.dispatch(hl.dsp.window.close({ window = "address:" .. w.address }))
          end
          break
        end
      end
    end
  end
end

Submap.define({
  name = "Delete",
  desc = "+Delete",
  enter = Config.leader .. " + D",

  escape = "reset",
  catchall = "reset",

  -- stylua: ignore start
  binds = {
    { "B",          close_by_class(CLASSES.browsers),     "Close Browsers"           },
    { "C",          Cmd.run("cliphist wipe"),             "Clear Clipboard"          },
    { "D",          close_workspace_windows(false),       "Close All on WS"          },
    { "SHIFT + D",  close_workspace_windows(true),        "Kill All on WS"           },
    { "E",          close_by_class(CLASSES.editors),      "Close Editors"            },
    { "F",          close_by_class(CLASSES.files),        "Close File Managers"      },
    { "G",          close_by_class(CLASSES.games),        "Close Games"              },
    { "M",          close_by_class(CLASSES.mail),         "Close Mail"               },
    { "N",          Cmd.run("swaync-client --close-all"), "Clear Notifications"      },
    { "O",          close_workspace_windows(false, true), "Close Others on WS"       },
    { "SHIFT + O",  close_workspace_windows(true, true),  "Kill Others on WS"        },
    { "P",          close_by_class(CLASSES.media),        "Close Media Players"      },
    { "S",          close_by_class(CLASSES.chat),         "Close Chat"               },
    { "T",          close_by_class(CLASSES.terminals),    "Close Terminals"          },
    { "W",          Window.close(),                       "Close Window"             },
    { "SHIFT + W",  Window.kill(),                        "Kill Window"              },
  },
  -- stylua: ignore end
}).setup()
