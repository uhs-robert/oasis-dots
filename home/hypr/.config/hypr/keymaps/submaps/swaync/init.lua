--- Swaync submap
--- Each bind runs a swaync command

local Config = require("config") ---@class Config
local Submap = require("lib.key.submap") ---@class Submap
local Cmd = require("lib.actions.cmd") ---@class Cmd

Submap.define({
  name = "Notifications",
  desc = "+Notifications",
  on_enter = Cmd.run("swaync-client -op"),
  on_exit = Cmd.run("swaync-client -cp"),

  escape = "reset",
  catchall = "stay",

  -- stylua: ignore
  binds = {
    { "C",          Cmd.run("swaync-client --close-all"),   "Clear all notifications",  { oneshot = true } },
    { "H",          Cmd.run("swaync-client --hide-latest"), "Hide latest popup" },
    { "A",          Cmd.run("swaync-client --hide-all"),    "Hide all popups" },
    { "D",          Cmd.run("swaync-client -d"),            "Toggle Do Not Disturb" },
    { "R",          Cmd.run("swaync-client -R"),            "Reload config" },
    { "S",          Cmd.run("swaync-client -rs"),           "Reload CSS" },
  },
}).setup()
