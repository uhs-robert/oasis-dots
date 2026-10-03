# Machine profiles

Machine-specific Hyprland configuration lives in this directory.

`default.lua` owns the baseline hardware configuration, including monitor layouts and DRM device ordering. This keeps physical-device details out of the shared `hyprland.lua` entrypoint, and doubles as the template for your own machine: copy it to `<hostname>.lua` and adjust the values for your hardware.

Optional hostname-specific overrides can further specialize that configuration. Create `<hostname>.lua` and return only the values that differ from the default configuration:

```lua
return {
  persistent_workspaces = 4,
  drm_devices = "/dev/dri/card0",
  app = {
    term = "foot",
  },
}
```

The loader uses `$HOSTNAME` first and falls back to `/etc/hostname`. Profiles are keyed by the short hostname (everything before the first `.`), and profile names must contain only `A-Z`, `a-z`, `0-9`, `_`, or `-`. Invalid hostnames and missing hostname profiles are ignored. Hostname-profile values take precedence over `default.lua`, so host-specific differences can be represented without duplicating the full configuration.

`path_prepend` lists extra directories placed ahead of the inherited `PATH` for everything Hyprland starts, for tools that live in your home directory:

```lua
return {
  path_prepend = { os.getenv("HOME") .. "/.npm-global/bin" },
}
```

`wallpaper_enabled = false` keeps the wallpaper rotator from starting on this machine, for a static setup in `custom/hyprpaper.conf`. `wallpaper_location = true` lets the wallpaper rotator follow the sun. It reads the location from the Quickshell bar's weather cache and only goes online (`ipinfo.io`, `open-meteo.com`) without a fresh one; see `extensions/wallpaper/README.md`.

Monitor settings saved from the Settings panel live in `~/.local/state/hypr/monitors.json`, keyed by monitor description (or connector name). Their fields win over the profile's `monitors` per monitor, and a missing or corrupt file is ignored.

Profiles hold values that `Config` reads while the subsystems load. Keybinds, window rules, sessions and anything else built on the loaded library go in your own config under `custom/` instead, whose `init.lua` runs after everything else; see `custom/README.md`.

Hostname profiles (`<hostname>.lua`) are personal to the machine they describe, so this directory's `.gitignore` untracks any file added here other than `default.lua`, `init.lua`, and this README. Copy `default.lua` to get started; your copy stays local and won't show up in `git status`.

On hybrid laptops (integrated and discrete GPU on the same system), apps render on the integrated GPU by default; to run a single app on the NVIDIA GPU instead, use `prime-run <app>`. To restore the old behaviour where all apps run on the discrete GPU, set `nvidia = { hybrid = false }` in a hostname profile. Steam is started through `prime-run` on hybrid machines so games use the NVIDIA GPU, at the cost of Steam's own UI keeping the dGPU awake while it's open. This covers native Steam only; for Flatpak Steam, run `flatpak override --user --env=__NV_PRIME_RENDER_OFFLOAD=1 --env=__VK_LAYER_NV_optimus=NVIDIA_only --env=__GLX_VENDOR_LIBRARY_NAME=nvidia com.valvesoftware.Steam` once instead.

The Settings panel's Default apps section saves `app.term`, `app.editor`, `app.gui_file_manager` and `app.tui_file_manager` to `~/.local/state/hypr/apps.json`. Those choices win over `default.lua` and `<hostname>.lua`; delete the file, or pick "Machine default" in the panel, to fall back to the profile.
