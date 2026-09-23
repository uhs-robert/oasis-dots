--- Swaync submap
--- Each bind runs a swaync command, or its Quickshell notification-center equivalent

local Config = require("config") ---@class Config
local Submap = require("lib.key.submap") ---@class Submap
local Cmd = require("lib.actions.cmd") ---@class Cmd

local is_qs = Config.shell == "quickshell"

-- Per-shell command for each action; swaync has no equivalent for reload rows under Quickshell.
local qs_cmd = {
  enter = Cmd.run("qs ipc call popup open notifications"),
  exit = Cmd.run("qs ipc call popup close"),
  clear_all = Cmd.run("qs ipc call notifications clear_all"),
  hide_latest = Cmd.run("qs ipc call notifications dismiss_latest"),
  hide_all = Cmd.run("qs ipc call notifications dismiss_all"),
  toggle_dnd = Cmd.run("qs ipc call notifications toggle_dnd"),
}

local sw_cmd = {
  enter = Cmd.run("swaync-client -op"),
  exit = Cmd.run("swaync-client -cp"),
  clear_all = Cmd.run("swaync-client --close-all"),
  hide_latest = Cmd.run("swaync-client --hide-latest"),
  hide_all = Cmd.run("swaync-client --hide-all"),
  toggle_dnd = Cmd.run("swaync-client -d"),
}

local cmd = is_qs and qs_cmd or sw_cmd

-- stylua: ignore
local binds = {
  { "C", cmd.clear_all,   "Clear all notifications", { oneshot = true } },
  { "H", cmd.hide_latest, "Hide latest popup" },
  { "A", cmd.hide_all,    "Hide all popups" },
  { "D", cmd.toggle_dnd,  "Toggle Do Not Disturb" },
}

if not is_qs then
  -- stylua: ignore start
  table.insert(binds, { "R", Cmd.run("swaync-client -R"),  "Reload config" })
  table.insert(binds, { "S", Cmd.run("swaync-client -rs"), "Reload CSS" })
  -- stylua: ignore end
end

Submap.define({
  name = "Notifications",
  desc = "+Notifications",
  on_enter = cmd.enter,
  on_exit = cmd.exit,

  escape = "reset",
  catchall = "stay",

  binds = binds,
}).setup()
