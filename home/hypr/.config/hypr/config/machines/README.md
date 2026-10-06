# Machine profiles

Machine-specific Hyprland configuration lives in this directory.

`default.lua` owns the baseline configuration and ships generic: an empty monitor list. This keeps physical-device details out of the shared `hyprland.lua` entrypoint, and doubles as the template for your own machine: copy it to `<hostname>.lua` and adjust the values for your hardware.

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

`input` sets the keyboard layout (`kb_layout`, default `"us"`, plus `kb_variant` and `kb_options`), key repeat (`repeat_rate`, `repeat_delay`), the pointer (`sensitivity`, `follow_mouse`), the touchpad (`natural_scroll`, `tap_to_click`, `disable_while_typing`) and `which_key_delay_ms`; defaults are in `config/init.lua`. And `appearance` sets `inactive_opacity` (default `0.5`), `dim_inactive` (default `true`) and `dim_strength` (default `0.2`) for unfocused windows:

```lua
return {
  input = { kb_layout = "us", kb_variant = "dvorak", kb_options = "compose:ralt" },
  appearance = { inactive_opacity = 0.9, dim_inactive = false },
}
```

`wallpaper_enabled = false` keeps the wallpaper rotator from starting on this machine, for a static setup in `custom/hyprpaper.conf`. `wallpaper_location = true` lets the wallpaper rotator follow the sun. It reads the location from the Quickshell bar's weather cache and only goes online (`ipinfo.io`, `open-meteo.com`) without a fresh one; see `extensions/wallpaper/README.md`.

Input settings saved from the Settings panel live in `~/.local/state/hypr/input.json` and win over the profile's `input` values; per-device `devices` entries still win for their device.

Monitor settings saved from the Settings panel live in `~/.local/state/hypr/monitors.json`, keyed by monitor description (or connector name). Their fields win over the profile's `monitors` per monitor, and a missing or corrupt file is ignored.

Profiles hold values that `Config` reads while the subsystems load. Keybinds, window rules, sessions and anything else built on the loaded library go in your own config under `custom/` instead, whose `init.lua` runs after everything else; see `custom/README.md`.

Hostname profiles (`<hostname>.lua`) are personal to the machine they describe, so this directory's `.gitignore` untracks any file added here other than `default.lua`, `init.lua`, and this README. Copy `default.lua` to get started; your copy stays local and won't show up in `git status`.

On hybrid laptops (integrated and discrete GPU on the same system), apps render on the integrated GPU by default; to run a single app on the NVIDIA GPU instead, use `prime-run <app>`. To restore the old behaviour where all apps run on the discrete GPU, set `nvidia = { hybrid = false }` in a hostname profile. Steam is started through `prime-run` on hybrid machines so games use the NVIDIA GPU, at the cost of Steam's own UI keeping the dGPU awake while it's open. This covers native Steam only; for Flatpak Steam, run `flatpak override --user --env=__NV_PRIME_RENDER_OFFLOAD=1 --env=__VK_LAYER_NV_optimus=NVIDIA_only --env=__GLX_VENDOR_LIBRARY_NAME=nvidia com.valvesoftware.Steam` once instead.

The Settings panel's Default apps section saves `app.term`, `app.editor`, `app.gui_file_manager` and `app.tui_file_manager` to `~/.local/state/hypr/apps.json`. Those choices win over `default.lua` and `<hostname>.lua`; delete the file, or pick "Machine default" in the panel, to fall back to the profile.

## Monitors

`monitors` is an ordered list of `{ description | name | id, mode, position, scale, transform?, primary? }` entries. A connected monitor matches an entry by description, name or id, and the entry's position in the list is the monitor's slot: the jump index for `Ctrl+<n>` and the Windows submap, and the workspace range `(slot-1)*persistent_workspaces+1` through `slot*persistent_workspaces` (1-5, 6-10, ... with the defaults). Lists replace the default instead of merging, so a hostname profile that sets `monitors` supplies the whole list:

```lua
return {
  monitors = {
    { description = "BOE 0x0C8E", mode = "2560x1600@240", position = "0x0", scale = 1.6 },
    { description = "Dell Inc. DELL U2723QE ABC1234", mode = "3840x2160@60", position = "1600x0", scale = 1.5, primary = true },
  },
}
```

Monitors that match no entry, including every monitor when the list is empty, still come up with their preferred mode, automatic position and scale 1. They take the lowest slots no matched monitor holds, in the order Hyprland connected them (by monitor id, then name), so the profile's length never shifts them: with an empty list the first output is slot 1, the second slot 2. A matched monitor always keeps its own slot, whether or not the others are connected, and an unmatched monitor never shares one. Slots depend only on which monitors are connected, so they survive reloads; a monitor that takes a free slot moves to the next free one when the entry that owns the slot is plugged back in.
