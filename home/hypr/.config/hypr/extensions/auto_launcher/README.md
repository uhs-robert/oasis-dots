# Session launcher

A workspace session launcher, picked in the Quickshell picker (or the dmenu command in `Config.app.dmenu_cmd`, rofi by default, when the bar is not running). A session is a named set of apps, each pinned to a specific monitor and workspace offset. `sessions.lua` ships a few generic ones (Browsing, Files, Game, System Monitor, System Update) built from your `Config.app` choices and common apps (Firefox, Steam, btop, topgrade). A session monitor that is not connected folds onto the highest connected one, so they work on any layout.

Trigger the picker with `SUPER + SHIFT + O`.

## Your own sessions

Your own sessions go in your `custom/` config and are registered on top of the defaults. `Sessions.term` runs a command in the configured terminal under its own window class, `Sessions.tmuxifier` loads a tmuxifier session, and a plain table launches any app:

```lua
-- custom/sessions.lua, required from custom/init.lua
local Sessions = require("extensions.auto_launcher.sessions")

Sessions.add("💼 Work", {
  { monitor = 1, ws = 1, cmd = "firefox --new-window", class = "org.mozilla.firefox" },
  Sessions.tmuxifier({ session = "work", monitor = 2, ws = 1 }),
  { monitor = 2, ws = 2, cmd = "slack", class = "slack", size = { 1064, 461 }, delay = 5000 },
})

Sessions.remove("🎮 Game") -- drop a default; Sessions.clear() drops them all
```

`Launcher.launch(name)` starts a session by exact name without the picker. voxcmd uses it for "open the work session" (see its [Sessions](../../../../../voxcmd/.config/voxcmd/README.md#sessions) section), with `Launcher.write_names(path)` to list them.

## Code

- `init.lua`: binds the picker key.
- `launcher.lua`: the picker, `Launcher.launch` and `Launcher.write_names`, and the window rules and placement that start each app.
- `sessions.lua`: the session registry, the shipped defaults, and sessions saved from the Settings Sessions tab (`sessions.json` in the state directory), which win over a Lua session of the same name.
- `prompt.lua`: the non-blocking dmenu prompt.
- `capture.lua`: turns open windows into draft session entries for the Settings Sessions tab.
- `provenance.lua`: remembers which entry opened each window, so capture saves the exact command.
