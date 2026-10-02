# Custom config

This directory is your own Hyprland config, run after this one. Once `hyprland.lua` has applied the machine profile, loaded every subsystem under `config/`, `keymaps/`, `extensions/` and `theme/`, and set up HyprVim, it runs `custom/init.lua` if one exists. From there you control everything: what loads, in what order, and how it's split into files. Any part of the library is a `require` away, and anything the shared config set can be overridden.

Everything in this directory other than `README.md` and `.gitignore` is gitignored, so your files stay local and never show up in `git status`.

## What goes where

- **Hardware and `Config` values** (monitors, DRM devices, GPU options, default apps) belong in `config/machines/<hostname>.lua`. The subsystems read `Config` while they load, so changing it from here is too late for them. See `config/machines/README.md`.
- **Everything built on the loaded library** belongs here: Hyprland settings, keybinds and submaps, window rules, event handlers, your own sessions for the session launcher.

## Layout

`custom/init.lua` is the entrypoint, the same way `hyprland.lua` is for this config. Split it up however you like and require your files as `custom.<name>`, which resolves to `custom/<name>.lua` or `custom/<name>/init.lua`:

```lua
-- custom/init.lua
require("custom.general")
require("custom.keymaps")
require("custom.rules")
require("custom.sessions")
```

Errors propagate like they do anywhere else in the config, so Hyprland reports a broken file the same way it reports its own. `hyprctl reload` reruns `hyprland.lua`, and your config with it.

## Examples

Hyprland settings, on top of `config/general/init.lua`:

```lua
-- custom/general.lua
hl.config({
  general = { gaps_in = 8, gaps_out = 16 },
  decoration = { rounding = 6 },
})
```

Keybinds, with the same helpers `keymaps/` uses. See [Keybinds](#keybinds) for overriding the ones this config ships:

```lua
-- custom/keymaps.lua
local Bind = require("lib.key.bind")

Bind.leader_cmd("SHIFT + B", "firefox --private-window", "Private browsing")
Bind.leader_fn("SHIFT + N", function() hl.notification.create({ text = "Hello", timeout = 2000 }) end, "Say hello")
```

Window rules and event handlers:

```lua
-- custom/rules.lua
hl.window_rule({ name = "float-calculator", match = { class = "org.gnome.Calculator" }, float = true })

hl.on("hyprland.start", function() hl.exec_cmd("nm-applet --indicator") end)
```

Sessions for the launcher (`SUPER + SHIFT + O`), added to the shipped defaults. `Sessions.term` wraps a command in the configured terminal under its own window class, `Sessions.tmuxifier` loads a tmuxifier session, and plain tables are any app. `Sessions.remove(name)` drops one default and `Sessions.clear()` drops them all:

```lua
-- custom/sessions.lua
local Sessions = require("extensions.auto_launcher.sessions")

Sessions.add("💼 Work", {
  { monitor = 1, ws = 1, cmd = "firefox --new-window", class = "org.mozilla.firefox" },
  Sessions.tmuxifier({ session = "work", monitor = 2, ws = 1 }),
  { monitor = 2, ws = 2, cmd = "slack", class = "slack", size = { 1064, 461 }, delay = 5000 },
})

Sessions.remove("🎮 Game")
```

## Keybinds

Binding a key that is already bound doesn't replace it: Hyprland keeps both and runs both. To override one of this config's global binds, remove it with `hl.unbind` first, then bind your own:

```lua
-- custom/keymaps.lua
local Bind = require("lib.key.bind")

hl.unbind("SUPER + SHIFT + O")
Bind.leader_cmd("SHIFT + O", "my-launcher", "My launcher")
```

`hl.unbind` removes the key from the global map and from every submap at once, so it can't change a key inside one submap without losing it everywhere else.
