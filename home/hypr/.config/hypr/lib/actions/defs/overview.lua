-- Keyless open and close for the two overviews beyond the keyed ones (`overview.*` in tools.lua, `tmux.overview`).
local Act = require("lib.act") ---@class ActionLib
local Ipc = Act.Ipc

Act.define("overview.toggle", {
  label = "Toggle Overview",
  intent = "Open the workspace overview, or close it when it is open.",
  run = Ipc("overview", "toggle"),
})

Act.define("overview.close", {
  label = "Close Overview",
  intent = "Close the workspace overview.",
  run = Ipc("overview", "close"),
})

Act.define("tmux.toggle", {
  label = "Toggle Tmux Overview",
  intent = "Open the tmux session overview, or close it when it is open.",
  run = Ipc("tmux_overview", "toggle"),
})

Act.define("tmux.close", {
  label = "Close Tmux Overview",
  intent = "Close the tmux session overview.",
  run = Ipc("tmux_overview", "close"),
})

Act.define("tmux.search", {
  label = "Search Tmux Overview",
  intent = "Open the tmux session overview with the search box focused.",
  run = Ipc("tmux_overview", "search"),
})
