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

Hostname profiles (`<hostname>.lua`) are personal to the machine they describe, so this directory's `.gitignore` untracks any file added here other than `default.lua`, `init.lua`, and this README. Copy `default.lua` to get started; your copy stays local and won't show up in `git status`.
