# Hyprland Config

A Lua-driven Hyprland setup for a fully keyboard-driven workflow. Vim-modal navigation via [HyprVim](https://github.com/uhs-robert/hyprvim) with whichkey for keybind discovery. Includes dedicated submaps for window/workspace management, application navigation, virtual cursor emulation (`wlrctl` and `wl-kbptr`), and more. Also includes a color theme switcher, custom workspace session launcher, and a time-of-day wallpaper rotation system.

## What's in here

| Path           | Purpose                                                  |
| -------------- | -------------------------------------------------------- |
| `hyprland.lua` | Entry point for machine config and session init          |
| `config/`      | Core config module (monitors, env, Nvidia, cursor, apps) |
| `keymaps/`     | All keybinds; one file per submap                        |
| `theme/`       | Color theme system with rofi picker                      |
| `hyprvim/`     | Vim-modal navigation layer                               |
| `extensions/`  | Workspace launcher, wallpaper, and other extensions      |
| `lib/`         | Shared Lua libraries (Bind, utils, key system)           |

## Using this config

#### 1. Make a Copy

Fork the repo then deploy with stow:

```bash
stow -d home hypr
hyprctl reload
```

Or just move the `hypr` directory into your `.config/`:

```bash
mv home/hypr/.config/hypr ~/.config/hypr
```

#### 2. Update your config settings

Edit `hyprland.lua` to set your monitors and any configuration overrides:

```lua
-- hyprland.lua
Config.setup({
  drm_devices = "/dev/dri/card1:/dev/dri/card2 Hyprland",
  monitors = {
    { description = "My Monitor", mode = "2560x1440@144", position = "0x0", scale = 1 },
  },
})
```

> [!TIP]
> All available options and their defaults are documented in `config/init.lua`.

## HyprVim

A vim-modal navigation layer for Hyprland. Activate with `SUPER + SPACE`, exit with `SUPER + ESCAPE`.

Provides `normal`/`insert`/`visual` modes (and more) with window navigation, workspace jumping, and a which-key popup that shows keybinds for all of your submaps.

> [!NOTE]
> See the [HyprVim repo](https://github.com/uhs-robert/hyprvim) for full documentation. Whichkey requires `eww`.

## Keybinds

Press `SUPER + /` to open a rofi picker showing all active keybinds for the current mode.

> [!TIP]
> All binds are defined in `hypr/keymaps/`, one file per submap.
>
> The whichkey from HyprVim also displays keybinds when entering any submap.

## Workspaces

Each monitor gets `ws_per_monitor` workspaces (default: 5). Workspaces are numbered sequentially across monitors: monitor 1 gets 1–5, monitor 2 gets 6–10, and so on.

The `persistent_workspaces` option pins that many workspaces per monitor so they always appear in the bar even when empty. It also switches workspace keybinds to monitor-local mode, number keys and cycle binds stay within the current monitor's range.

## App Launcher / Sessions

`extensions/auto_launcher/` provides a rofi-based workspace session launcher. A session is a named set of apps, each pinned to a specific monitor and workspace offset. Sessions are defined in `sessions.lua`:

```lua
-- extensions/auto_launcher/sessions.lua
M.sessions = {
  ["Work"] = {
    { monitor = 1, ws = 1, cmd = "kitty", class = "kitty" },
    { monitor = 2, ws = 1, cmd = "firefox", class = "firefox" },
  },
}
```

Trigger the picker with `SUPER + SHIFT + O`.

## Wallpaper

`extensions/wallpaper/` is a time-of-day wallpaper rotation system built on hyprpaper. It picks wallpapers from different folders based on solar position (morning/day/evening/night) and rotates on a configurable interval.

Configure directories and timing in `extensions/wallpaper/config.lua`.

## Theme

```bash
~/.config/hypr/theme/main.lua --menu   # interactive picker
~/.config/hypr/theme/main.lua --list   # list palettes
```
