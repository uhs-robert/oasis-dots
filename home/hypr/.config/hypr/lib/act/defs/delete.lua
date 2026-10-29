-- Actions for the Delete submap: close or kill windows in bulk. Keyless; the Delete rows bind them. The notification
-- and single-window rows reuse `notifications.clear_all`, `window.close` and `window.kill`.
local Act = require("lib.act") ---@class ActionLib

-- Kept equal to the groups in lib/actions/delete.lua by act_stateful.lua; that module needs the session to load.
local GROUPS = { "browsers", "chat", "editors", "files", "games", "mail", "media", "terminals" }

Act.define("delete.close_workspace", {
  label = "Close Windows on Workspace",
  intent = "Close every window on the active workspace, or kill them; optionally keep the focused one.",
  params = {
    { name = "kill", type = "bool", default = false },
    { name = "except_active", type = "bool", default = false },
  },
  run = function(kill, except_active) require("lib.actions.delete").close_workspace(kill, except_active)() end,
})

Act.define("delete.close_group", {
  label = "Close App Group",
  intent = "Close every window of one kind of app (browsers, mail, chat, terminals, editors, files, games, media), or kill them.",
  params = {
    { name = "group", type = "enum", values = GROUPS },
    { name = "kill", type = "bool", default = false },
  },
  run = function(group, kill) require("lib.actions.delete").close_class(group, kill)() end,
})

Act.define("delete.clear_clipboard", {
  label = "Clear Clipboard",
  intent = "Wipe the clipboard history.",
  run = Act.Cmd("cliphist", "wipe"),
})
