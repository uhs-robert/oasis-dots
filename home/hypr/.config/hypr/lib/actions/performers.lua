--- The Lua performers of the action manifest: one function per action id bound `lua` in oasis-djinn's
--- bindings/hyprland.json. Bind.action calls a function in-process; `oasis-djinn <id>` reaches the same one through
--- `hyprctl eval 'require("lib.actions.performers").run("<id>", ...)'`, params arriving as Lua values.
---
--- Keep each function a `["<id>"] = function` row of `by_id`: the registry check reads the ids from this file as text.

local Menu = require("lib.actions.menu") ---@class Menu

--- Picker actions build their command from Config once, at load, like the binds they replace.
local clipboard = Menu.clipboard()
local clipboard_delete = Menu.clipboard_delete()
local directory = Menu.zoxide()
local emoji = Menu.emoji()

--- @type table<string, fun(...)>
local by_id = {
  -- The pickers fall back to rofi when the bar is down or lacks the provider, which a bar IPC binding cannot.
  ["picker.clipboard"] = function() clipboard() end,
  ["picker.clipboard_delete"] = function() clipboard_delete() end,
  ["picker.directory"] = function() directory() end,
  ["picker.emoji"] = function() emoji() end,
  -- Required on use, not at load: hyprvim is optional (repos/hyprvim) and loads after the keymaps.
  ["hyprvim.terminal"] = function() require("lua.plugins.hyprvim").command.prompt() end,
  ["hyprvim.jump_mark"] = function() require("lua.plugins.hyprvim").marks.enter_jump() end,
}

--- @class Performers
local Performers = {}

--- The function performing `id`, or nil when this module has none.
--- @param id string
--- @return fun(...)|nil
function Performers.get(id) return by_id[id] end

--- Perform `id` with its params. Raises on an id this module lacks, so `hyprctl eval` exits non-zero and
--- oasis-djinn reports the failure; returns nothing, so eval prints only its own "ok".
--- @param id string
function Performers.run(id, ...)
  local perform = by_id[id]
  if not perform then error("no Lua performer for action '" .. tostring(id) .. "'", 0) end
  perform(...)
end

return Performers
