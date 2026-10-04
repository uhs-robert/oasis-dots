# Hyprland Config

A Lua-driven Hyprland setup for a fully keyboard-driven workflow. Vim-modal navigation via [HyprVim](https://github.com/uhs-robert/hyprvim) with whichkey for keybind discovery. Includes dedicated submaps for window/workspace management, application navigation, virtual cursor emulation (`wlrctl` and `wl-kbptr`), and more. Also includes a color theme switcher, custom workspace session launcher, and a time-of-day wallpaper rotation system. The bar, popups, pickers and lock screen come from the [Quickshell desktop shell](#desktop-shell).

Requires a Hyprland build with the Lua config API (the `hl` global) and `start-hyprland`, which the current `hyprland` package from the Arch repos provides.

## What's in here

| Path                  | Purpose                                                  |
| --------------------- | -------------------------------------------------------- |
| `hyprland.lua`        | Entry point for machine config and session init          |
| `config/`             | Core config module (monitors, env, Nvidia, cursor, apps) |
| `custom/`             | Your own config via `custom/init.lua`, run last          |
| `keymaps/`            | All keybinds; one file per submap                        |
| `theme/`              | Oasis color themes, the switcher and the generators      |
| `lua/plugins/hyprvim` | Vim-modal navigation layer                               |
| `extensions/`         | Workspace launcher, wallpaper, and other extensions      |
| `lib/`                | Shared Lua libraries (Bind, utils, key system)           |
| `scripts/`            | Shell helpers, including the Quickshell IPC wrappers     |

## Using this config

#### 1. Install it

The easiest route is the full installer from the [repo root](../../../../README.md), which sets up everything this config expects.

To take just the Hyprland config, clone the repo and stow it. Run `just repos` first: the theme palettes and HyprVim are symlinks into `repos/`, and they stay broken until it has cloned them.

```bash
just repos        # clone oasis.nvim, HyprVim and the other external repos into repos/
just stow hypr    # link home/hypr into ~/.config/hypr
hyprctl reload
```

On its own it still expects a few neighbours: the bar, popups and lock screen come from the `quickshell` package, the pickers fall back to `rofi`, and some binds call tools like `wl-kbptr`, `wlrctl` and `hyprpaper` (see `packages/arch.ini` and `packages/arch-aur.ini`). Moving the folder by hand instead of stowing it breaks those symlinks.

Stow links `~/.config/hypr` as a whole directory into the checkout, so files this config generates land inside the repo and are gitignored: your machine profile (`config/machines/<hostname>.lua`), `custom/`, and `theme.conf`. The generators also write the rofi, foot, yazi, kitty and ghostty theme files into those packages' stowed config dirs, and `systemctl --user enable` adds `.wants` links under `home/systemd/`. Quickshell's `theme.json`, the Settings panel state, the selected palette (`hypr/theme`) and the `term` launcher wrapper (`hypr/bin/term`, on `PATH`) go to `$XDG_STATE_HOME` (default `~/.local/state`), outside the checkout.

#### 2. Set up your machine

With the Quickshell shell running, most of this is in its Settings panel (`SUPER + SPACE` then `S`): Displays sets resolution, refresh rate, scale and arrangement with a keep-or-revert countdown, Default apps picks the terminal, editor and file managers, and Power sets idle timeouts and lid actions. Those choices are saved as state under `~/.local/state/hypr/`, and the display and app choices win over the machine profile below.

The files are the tracked defaults, and the only place for things Settings doesn't cover, such as DRM devices or GPU options. Machine settings live in `config/machines/`, not `hyprland.lua`. Copy `config/machines/default.lua` to `config/machines/<hostname>.lua` and set what differs on that machine:

```lua
-- config/machines/<hostname>.lua
return {
  drm_devices = "/dev/dri/card1:/dev/dri/card2 Hyprland",
  monitors = function()
    return {
      { description = "My Monitor", mode = "2560x1440@144", position = "0x0", scale = 1 },
    }
  end,
}
```

The loader picks this up automatically by hostname; see `config/machines/README.md` for details. Anything in `config/machines/` other than `default.lua`, `init.lua`, and its README is gitignored, so your profile stays local.

> [!TIP]
> All available options and their defaults are documented in `config/init.lua`.

#### 3. Add your own config

`custom/` is your own Hyprland config, run after this one. Once every subsystem and HyprVim have loaded, `hyprland.lua` runs `custom/init.lua` if it exists; from there you decide what loads and in what order, `require` anything in the library (`lib.key.bind`, `config`, the session registry) and override what the shared config set. The directory is gitignored apart from its README, so your files stay local.

```lua
-- custom/init.lua
require("custom.keymaps") -- custom/keymaps.lua

hl.config({ general = { gaps_in = 8, gaps_out = 16 } })
```

See `custom/README.md` for the layout and more examples, including sessions for the launcher.

## HyprVim

A vim-modal navigation layer for Hyprland. Activate with `SUPER + V`, exit with `SUPER + ESCAPE`.

Provides `normal`/`insert`/`visual` modes (and more) with window navigation, workspace jumping, and a which-key popup that shows keybinds for all of your submaps.

> [!NOTE]
> See the [HyprVim repo](https://github.com/uhs-robert/hyprvim) for full documentation. This setup runs its which-key HUD and `:` prompt on the Quickshell frontend.
>
> `lua/plugins/hyprvim` is a symlink into the dotfiles `repos/` directory, which the installer fills with a HyprVim clone.

## Keybinds

Press `SUPER + /` to open the Quickshell keybinds picker for the current mode. When the bar isn't running it falls back to the rofi script (`scripts/keybind-help.lua`).

> [!TIP]
> All binds are defined in `hypr/keymaps/`, one file per submap. [Changing keybinds](../../../../docs/keybinds.md) shows how to change them and add your own from `custom/`, without editing these files.
>
> To override one from your `custom/` config, remove it with `Bind.unbind(key, submap)` and bind your own. Hyprland's `hl.unbind` can't target one submap ([hyprwm/Hyprland#15040](https://github.com/hyprwm/Hyprland/discussions/15040)), so `Bind` tracks its binds per submap; see `custom/README.md`.
>
> The whichkey from HyprVim also displays keybinds when entering any submap.

## Workspaces

Each monitor gets `persistent_workspaces` workspaces (default: 5; 5 when set to `false`). Workspaces are numbered sequentially across monitors: monitor 1 gets 1–5, monitor 2 gets 6–10, and so on.

That option pins them so they always appear in the bar even when empty. It also switches workspace keybinds to monitor-local mode, number keys and cycle binds stay within the current monitor's range.

## App Launcher / Sessions

`extensions/auto_launcher/` provides a workspace session launcher, picked in the Quickshell picker (or the dmenu command in `Config.app.dmenu_cmd`, rofi by default, when the bar isn't running). A session is a named set of apps, each pinned to a specific monitor and workspace offset. `sessions.lua` ships a few generic ones (Browsing, Files, Game, System Monitor, System Update) built from your `Config.app` choices and common apps (Firefox, Steam, btop, topgrade); a session monitor that is not connected folds onto the highest connected one, so they work on any layout.

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

Trigger the picker with `SUPER + SHIFT + O`.

## Wallpaper

`extensions/wallpaper/` rotates wallpapers through hyprpaper, picking from folders that match the season, the part of the day and the weather. No wallpapers ship with this repo, since the images are other artists' copyrighted work; bring your own collection in one layout, `<Season>/<Period>/<Weather>/`, such as `Fall/Night/Rain`.

See [`extensions/wallpaper/README.md`](extensions/wallpaper/README.md) for setting up a collection, how it picks, settings and troubleshooting.

## Theme

The colors come from the Oasis palettes in `theme/colors/`. Picking one saves it, reloads Hyprland and reruns every generator in `theme/generate/` (Hyprland, rofi, the terminals and Quickshell, whose `theme.json` lands in `~/.local/state/quickshell/`).

The rofi `colors.rasi`, foot `foot.ini` and yazi `theme.toml` are generated and gitignored. Edit their tracked `colors.template.rasi`, `foot.template.ini` and `theme.template.toml` instead; the installer copies each one into place when the generated file is missing. Deploy these packages with `just stow <pkg>` (or the installer), not bare `stow`, so that step runs.

Pick a palette from Settings > Colors in the Quickshell panel, with a live preview. Right-clicking the bar's Start button or pressing `SUPER + Q` then `T` opens it there; without the bar, `SUPER + Q` then `T` falls back to the rofi picker.

```bash
~/.config/hypr/theme/switch.lua                     # rofi picker (the fallback)
~/.config/hypr/theme/switch.lua --set oasis_lagoon  # set one directly
```

## Desktop shell

The bar, popups, notifications, pickers, workspace overview, lock screen and greeter are one Quickshell config. Hyprland starts it at login and talks to it through `scripts/qs-ipc`, falling back to rofi or hyprlock when it isn't running. See the [Quickshell README](../../../quickshell/.config/quickshell/README.md) for styles, settings, keys and IPC.
