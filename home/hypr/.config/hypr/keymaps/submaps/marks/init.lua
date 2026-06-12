--- Marks submap
--- Each bind calls hyprvim to use Marks system

local Config = require("config") --- @class Config
local Apps = require("lib.actions.apps") --- @class Apps
local Cmd = require("lib.actions.cmd") --- @class Cmd
local Menu = require("lib.actions.menu") --- @class Menu
local Submap = require("lib.key.submap") --- @class Submap

local function set_hyprvim_mark() require("lua.plugins.hyprvim").marks.enter_set() end
local function jump_to_hyprvim_mark() require("lua.plugins.hyprvim").marks.enter_jump() end
local function delete_hyprvim_mark() require("lua.plugins.hyprvim").marks.enter_delete() end

Submap.define({
  name = "Marks",
  desc = "+Marks",
  enter = Config.leader .. " + APOSTROPHE",

  escape = "reset",
  catchall = "stay",

  -- stylua: ignore
  binds = {
    { "APOSTROPHE", jump_to_hyprvim_mark, "Jump to mark" },
    { "M",          set_hyprvim_mark,     "Set mark" },
    { "D",          delete_hyprvim_mark,  "Delete mark" },
  },
}).setup()
