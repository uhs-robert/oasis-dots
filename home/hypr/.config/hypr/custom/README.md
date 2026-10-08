# Custom config

This directory is your own Hyprland config, run after this one. Once `hyprland.lua` has applied the machine profile, loaded every subsystem under `config/`, `keymaps/`, `extensions/` and `theme/`, and set up HyprVim, it runs `custom/init.lua` if one exists. From there you control everything: what loads, in what order, and how it's split into files. Any part of the library is a `require` away, and anything the shared config set can be overridden.

Everything in this directory other than `README.md` and `.gitignore` is gitignored, so your files stay local and never show up in `git status`.

## Keeping your files

Being gitignored keeps your files out of this repo, not out of version control. To track them and carry them between machines, keep them in a repo of your own and link each file in:

```bash
ln -s ~/my-dots/hypr/custom/init.lua      ~/.config/hypr/custom/init.lua
ln -s ~/my-dots/hypr/custom/wallpaper.lua ~/.config/hypr/custom/wallpaper.lua
ln -s ~/my-dots/hypr/machines/laptop.lua  ~/.config/hypr/config/machines/laptop.lua
```

Link files, not the `custom/` directory itself: this README and `.gitignore` are tracked here and must stay in place. A loop in your own installer that links every file in those folders keeps new ones picked up.

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

Entry fields: `monitor`, `ws`, `cmd`, `class` or `title` (how the launcher finds the window it opened), `size`, `pos`, `delay`, plus:

- `special = "scratchpad"` launches onto `special:scratchpad` instead of `monitor`/`ws`, which are then not needed.
- `float = true` floats the window before `size` and `pos` apply.
- `guessed = true` marks a command reconstructed from `/proc` when a session was saved. The launcher runs the command as written either way; the flag only makes Settings mark it for you to check.

Lua sessions launch every entry at once. `Sessions.add(name, apps, { sequential = true })` instead launches tiled entries one at a time, in order, each window taking focus so the layout comes out the same every run; floating and special entries still launch at once.

### Saved sessions

Sessions saved from Settings live in `~/.local/state/hypr/sessions.json` (`$XDG_STATE_HOME/hypr`), re-read each time the picker opens. They launch sequentially and win over a Lua session of the same name. A symlink there is followed, so it can point at a backup copy. A missing file means no saved sessions; a malformed one raises a notification.

```json
{
  "version": 1,
  "sessions": {
    "Work": {
      "windows": [
        { "monitor": 1, "ws": 1, "cmd": "firefox --new-window", "class": "org.mozilla.firefox" },
        { "monitor": 1, "ws": 1, "cmd": "kitty --class k-notes", "class": "k-notes", "size": [900, 1000], "guessed": true },
        { "special": "scratchpad", "cmd": "slack", "class": "slack", "float": true, "size": [1064, 461], "pos": [100, 80] }
      ]
    }
  }
}
```

## Wallpaper

The wallpaper rotator runs as its own process, so it reads its settings from files here rather than from `custom/init.lua`. Both are optional:

- `custom/wallpaper.lua` returns a table merged over `extensions/wallpaper/config.lua`, so it only needs the values you change.
- `custom/hyprpaper.conf` replaces the shipped `hyprpaper.conf` when the rotator starts hyprpaper. Keep `ipc = true` in it, since the rotator sets wallpapers over IPC.

```lua
-- custom/wallpaper.lua
return {
  wallpaper_dir = os.getenv("HOME") .. "/Pictures/Walls",
  interval_minutes = 30,
  weather_chance = 0.4,
}
```

To skip the rotator on a machine, set `wallpaper_enabled = false` in its profile under `config/machines/`; hyprpaper then needs starting from `custom/init.lua`, with your `custom/hyprpaper.conf`.

## Keybinds

[Changing keybinds](../../../../../docs/keybinds.md) is the full guide: adding binds, replacing shipped ones, changing a key inside one submap, and defining submaps of your own, all from `custom/keymaps.lua`. The short version:

```lua
-- custom/keymaps.lua, required from custom/init.lua
local Bind = require("lib.key.bind")

-- Binding a taken key runs both binds, so remove the shipped one first.
Bind.leader_unbind("SHIFT + O")
Bind.leader_cmd("SHIFT + O", "my-launcher", "My launcher")

-- Inside one submap only: H in Windows; H elsewhere is untouched.
Bind.unbind("H", "Windows")
Bind.submap("Windows", function() Bind.key("H", hl.dsp.focus({ direction = "left" }), "Focus left") end)
```

### Why not `hl.unbind`

Hyprland has no way to unbind a key in just one submap. `hl.unbind(key)` removes that key from the global map and from every submap at once, and through Hyprland 0.56 the handle `hl.bind` returns does the same when you call `:remove()` on it. That makes it impossible to change one submap's `H` without losing `H` everywhere else. The request for a scoped unbind is still open upstream: [hyprwm/Hyprland#15040](https://github.com/hyprwm/Hyprland/discussions/15040).

`Bind` works around it. Every bind made through it keeps its handle, filed under the submap it was made in, and `Bind.unbind` acts on those handles only:

- **Hyprland 0.57 and newer** remove the bind outright; the keybind rewrite after 0.56 made `:remove()` drop just that one bind.
- **Hyprland 0.56 and older**, and `-git` builds that still report 0.56, disable the bind instead. It no longer fires, but `hyprctl binds` still lists it, so it still shows up in the `SUPER + /` picker and the which-key HUD, and choosing it from the picker still runs it.

Only binds made through `Bind` are tracked. HyprVim's own binds, and anything made with a raw `hl.bind`, can only be dropped with `hl.unbind`, which removes the key from every submap.

`Bind.unbind` and `Bind.submap` are the supported way to override binds and are here to stay. If Hyprland adds its own way to unbind a key in one submap, `Bind.unbind` will use it underneath, so configs that call it keep working unchanged.
