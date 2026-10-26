-- Keyless actions for the notification center: no key calls them, so the bar, voice and `hypr-act` are the callers.
local Act = require("lib.act") ---@class ActionLib
local Ipc = Act.Ipc

Act.define("notifications.toggle_dnd", {
  label = "Toggle Do Not Disturb",
  intent = "Mute or unmute notification toasts and sounds; notifications still collect in the center.",
  run = Ipc("notifications", "toggle_dnd"),
})

Act.define("notifications.clear_all", {
  label = "Clear Notifications",
  intent = "Remove every notification from the center and from the screen.",
  run = Ipc("notifications", "clear_all"),
})

Act.define("notifications.dismiss_latest", {
  label = "Dismiss Latest Toast",
  intent = "Hide the newest toast on screen; it stays in the center.",
  run = Ipc("notifications", "dismiss_latest"),
})

Act.define("notifications.dismiss_all", {
  label = "Dismiss All Toasts",
  intent = "Hide every toast on screen; they stay in the center.",
  run = Ipc("notifications", "dismiss_all"),
})
