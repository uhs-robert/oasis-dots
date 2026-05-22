-- home/hypr/.config/hypr/extensions/auto_launcher/init.lua
local Config = require("config") ---@class Config

--- @type table<string, HL.WindowRule>
_G.auto_launcher_rules = {}

--- Creates (once) and enables a named workspace window rule, then disables it after 30s.
--- Called via `hyprctl eval` from the launcher for forking processes (flatpak, Electron)
--- that ignore exec_cmd workspace hints because they spawn windows from a child process.
--- @param match_key "class"|"title" which window property to match
--- @param match_value string regex value to match against
--- @param workspace integer absolute workspace number to pin the window to
function _G.enable_workspace_rule(match_key, match_value, workspace)
  local key = match_key .. "-" .. match_value .. "-" .. tostring(workspace)
  if not _G.auto_launcher_rules[key] then
    _G.auto_launcher_rules[key] = hl.window_rule({
      name = "workspace-app-" .. key:gsub("[^%w%-]", "-"),
      match = { [match_key] = match_value },
      workspace = tostring(workspace) .. " silent",
    })
    _G.auto_launcher_rules[key]:set_enabled(false)
  end
  _G.auto_launcher_rules[key]:set_enabled(true)
  hl.timer(function() _G.auto_launcher_rules[key]:set_enabled(false) end, { timeout = 30000, type = "oneshot" })
end

hl.bind(
  Config.leader .. " + SHIFT + O",
  hl.dsp.exec_cmd(
    string.format(
      "lua ~/.config/hypr/extensions/auto_launcher/launch.lua %d '%s'",
      Config.ws_per_monitor,
      Config.app.term_cmd
    )
  ),
  { description = "Workspace App Launcher" }
)
