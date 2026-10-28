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

On its own it still expects a few neighbours: the bar, popups, pickers and lock screen come from the `quickshell` package, and some binds call tools like `wl-kbptr`, `wlrctl` and `hyprpaper` (see `packages/arch.ini` and `packages/arch-aur.ini`). When Quickshell is not running, the pickers fall back to the menu in `Config.app.menu`. The default, `rofi`, covers all of them. With `fuzzel` or `wofi` the app launcher opens natively and the run, ssh and window pickers go through `Config.app.dmenu_cmd`; any other dmenu-style menu gets those three but no app launcher. The keybind fallback, the tmux session picker and Bitwarden (`rofi-rbw`) always use rofi. Moving the folder by hand instead of stowing it breaks those symlinks.

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

The loader picks this up automatically by hostname; see `config/machines/README.md` for details, including `Config.input` (keyboard layout) and `Config.appearance` (inactive window opacity and dimming). Anything in `config/machines/` other than `default.lua`, `init.lua`, and its README is gitignored, so your profile stays local.

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

While Quickshell's screen frame is on (Settings > Theme options > Screen frame), `config/general/frame.lua` sets `decoration.rounding`, `decoration.rounding_power`, `general.border_size` and the border colours to match the frame, and puts your values back when the frame goes; values you set from `custom/` are the ones it restores. For the chamfer, pixel-art corners it adds a window rule matching every window, and for windows that sit flush with the frame (maximized, or the only tiled window on a workspace) rules giving them the frame's full corner; these are made when the frame is first applied, so they sort after your own rules and override a `rounding` or `rounding_power` rule of yours on those windows while the frame is on. A style with no border leaves your border size and colours alone. SUPER+M on a lone tiled window (already flush) toggles that flush off and on instead of maximizing, with your gaps and the gapped rounding while off; it ends by itself when a second tiled window arrives, floats or leaves, and is kept across a frame change that leaves the window alone. While the frame is on, the workspace switch animation uses a bezier without overshoot (flush windows would bounce past the frame), and the config's own animation is put back when the frame goes.

With the frame on, a workspace with a single tiled window drops its outer gaps so the window sits flush inside the frame, and the gaps return with a second tiled window. `SUPER + M` maximizes the focused window inside the frame and bar with no outer gaps, and again restores it; `SUPER + F` stays true fullscreen. The Move submap is on `SUPER + SHIFT + M`.

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

Trigger the picker with `SUPER + SHIFT + O`. `Launcher.launch(name)` starts a session by exact name without the picker; voxcmd uses it for "open the work session" (see its [Sessions](../../../voxcmd/.config/voxcmd/README.md#sessions) section), with `Launcher.write_names(path)` to list them.

## Wallpaper

`extensions/wallpaper/` rotates wallpapers through hyprpaper, picking from folders that match the season, the part of the day and the weather. No wallpapers ship with this repo, since the images are other artists' copyrighted work; bring your own collection in one layout, `<Season>/<Period>/<Weather>/`, such as `Fall/Night/Rain`.

See [`extensions/wallpaper/README.md`](extensions/wallpaper/README.md) for setting up a collection, how it picks, settings and troubleshooting.

## Theme

The colors come from the Oasis palettes in `theme/colors/`. Picking one saves it, reloads Hyprland and reruns every generator in `theme/generate/` (Hyprland, rofi, the terminals, Quickshell, whose `theme.json` lands in `~/.local/state/quickshell/`, and Neovim when synced).

The rofi `colors.rasi`, foot `foot.ini` and yazi `theme.toml` are generated and gitignored. Edit their tracked `colors.template.rasi`, `foot.template.ini` and `theme.template.toml` instead; the installer copies each one into place when the generated file is missing. Deploy these packages with `just stow <pkg>` (or the installer), not bare `stow`, so that step runs.

Pick a palette from Settings > Style in the Quickshell panel (its Colors rows), with a live preview. Right-clicking the bar's Start button opens it there; without the bar, run `~/.config/hypr/theme/switch.lua` for the rofi picker.

```bash
~/.config/hypr/theme/switch.lua                     # rofi picker (the fallback)
~/.config/hypr/theme/switch.lua --set oasis_lagoon  # set one directly
```

Neovim keeps its own colorscheme unless Settings > Style > Sync Neovim is on (off by default). With it on, the matching oasis.nvim scheme (`oasis-lagoon` for `oasis_lagoon`) is written to `~/.local/state/hypr/nvim-colorscheme` and pushed to every running Neovim over its RPC socket. For new Neovim sessions to start in it, have your config read that file when it exists and apply it once oasis.nvim is loaded:

```lua
local f = io.open((vim.env.XDG_STATE_HOME or vim.env.HOME .. "/.local/state") .. "/hypr/nvim-colorscheme")
local colorscheme = f and vim.trim(f:read("*a")) or "oasis"
if f then f:close() end
vim.cmd.colorscheme(colorscheme) -- or pass it to your plugin manager, e.g. LazyVim's `opts.colorscheme`
```

## Desktop shell

The bar, popups, notifications, pickers, workspace overview, lock screen and greeter are one Quickshell config. Hyprland starts it at login and talks to it through `scripts/qs-ipc`, falling back to the `Config.app.menu` launcher (rofi by default) or hyprlock when it isn't running. See the [Quickshell README](../../../quickshell/.config/quickshell/README.md) for IPC, the [theme README](../../../quickshell/.config/quickshell/theme/README.md) for styles, the [settings README](../../../quickshell/.config/quickshell/features/settings/README.md) for settings and the [popups README](../../../quickshell/.config/quickshell/features/popups/README.md) for keys.

## Code

The config is Lua, not `hyprland.conf`, and the tree is stylua-checked.

- `hyprland.lua` is the entrypoint: it merges the machine config (`config/machines/`), loads the `hyprvim` plugin and requires `custom/init.lua` last. Subsystems live in `config/`, `keymaps/`, `extensions/`, `lib/`, `scripts/` and `theme/`.
- Actions (`lib/act.lua`): each thing the desktop can do is defined once with `Act.define` in `lib/actions/defs/` (`tools.lua` for the tool keys, `pickers.lua` for the pickers and HyprVim keys, one file per bar area for the keyless IPC actions). A defs file is live only if a keymap requires it (`keymaps/global/tools.lua`, `keymaps/global/keyless.lua`). `Act.bind` adds another key with args; `Act.run` and `Act.run_cli` run one by id. `hypr-act list` and `hypr-act <id> [args...]` (`home/hypr/.local/bin/hypr-act`) list and run them in the live session; its header lists the exit codes.
- The `registry` check step loads the defs under stubs (`home/hypr/tests/act_refs.lua`, which needs a stub line for any new `require`) and checks the ids, IPC functions and scripts they name. A new bind or typed IPC function needs an action, or a reasoned line in `lib/check/registry.allow`.
- Keys: register binds through `lib/key/bind.lua` (`Bind.key`, `Bind.submap`), never raw `hl.bind` or `hl.define_submap`, so `Bind.unbind` can remove a key from one submap. `Bind.unbind` and `Bind.submap` are public API for `custom/`; keep their signatures stable.
- Overrides stay out of tracked files: machine values in `config/machines/<hostname>.lua`, everything else in `custom/` (see [Add your own config](#3-add-your-own-config)). Never auto-load other `custom/` files from the config; the wallpaper rotator, a separate process, is the one reader of `custom/wallpaper.lua` and `custom/hyprpaper.conf`.
