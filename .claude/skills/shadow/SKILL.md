---
name: shadow
description: Run the full Quickshell bar in an invisible, isolated nested Hyprland and drive it (IPC, keys) and screenshot it without touching the owner's screen. Use to check any Quickshell surface or branch visually, or to drive popups and keys; prefer it over live self-tests on the owner's bar.
---

# Shadow bar

`shadow.sh` runs a copy of the bar inside a nested Hyprland on a headless host compositor. Nothing appears on the owner's screen, and nothing reaches their Hyprland, bar, input or session bus. It is the only way for agents to look at or drive a surface or take a screenshot. Reading the owner's live session (`hyprctl -j` queries, non-sensitive state JSON, logs) needs no permission; see `owner-test-bar` for what changing it needs. `owner-test-bar` is for putting a branch on the owner's real screen for the owner to try.

```
.claude/skills/shadow/shadow.sh up <name> [--size WxH] [--desktop] [<branch>...]   # default 1920x1080; bar from the main checkout, or from branches merged on origin/main
.claude/skills/shadow/shadow.sh spawn <name> [<command>...]   # a client in the shadow, default foot; returns once its window maps
.claude/skills/shadow/shadow.sh ipc <name> popup open weather   # qs ipc call; `ipc <name> show` lists targets
.claude/skills/shadow/shadow.sh wait <name> popup weather    # until it is fully drawn; also `osd voxtype`, `popup closed`, or `clickhints open`/`closed`; default --timeout 5
.claude/skills/shadow/shadow.sh keys <name> 2              # wtype args, e.g. `-k Tab`, `-M ctrl -k l -m ctrl`
.claude/skills/shadow/shadow.sh voxtype <name> recording   # idle|recording|transcribing: the only way to raise the OSD, since there is no PipeWire
.claude/skills/shadow/shadow.sh hyprctl <name> layers -j
.claude/skills/shadow/shadow.sh shot <name> [<layer namespace>] [--pad N] [--out PATH]   # no namespace: whole output at the shadow size
.claude/skills/shadow/shadow.sh status [<name>]
.claude/skills/shadow/shadow.sh down <name> [--keep]
```

`smoke.sh [--out DIR] [--name SHADOW] [--dry-run] [--self-test] [style...]` runs one pass per style on a shadow (its own `smoke`, brought up and down unless `--name` names a running one): popup, OSD (voxtype recording), which-key, the click-hints overlay (fixture boxes) and the region selector, then a contact sheet `sheet.png` and a log check. It records `MISS <style> <surface>-blank` when a capture matches what lies behind it. The which-key HUD is fed a fixture payload through its `hyprvim_whichkey` IPC target because the shadow loads no HyprVim, so it shows the HUD's drawing in each style, not the owner's real key rows. The volume and brightness OSDs cannot be raised (no PipeWire, no backlight writes).

`picker-race.sh [--name SHADOW] [<branch>...]` is the manual repro for the `choices` picker load race (#1067): it opens a second picker while the first spec is still unread (a FIFO), then three in a row, and asserts every caller's result file is written. With no branch it tests the main checkout; pass the branch under test to test it. It is not in `lib/check` because it needs a nested Hyprland and about a minute; run it when touching `ChoicesProvider.qml` or `Pickers.qml`.

`keeptabs-seq.sh [--name SHADOW] [<branch>...]` checks the keeptabs-status restart: a stub `keeptabs-status` in the shadow HOME is fed canned lines (the shadow's PATH hides the real one) and the shadow's copy of `KeeptabsState.qml` is patched to log each `waiting_started`. It asserts the priming line after a restart does not fire and the next waiting rise does, including when a quiet stream restarts with a first line identical to its old last line. With no branch it tests the main checkout. It takes about a minute (restart backoff); run it when touching `KeeptabsState.qml`.

`--size WxH` sets the output size, e.g. `--size 1080x1920` for the owner's portrait monitor; use it instead of an offscreen render for odd sizes. It is recorded in the shadow's state, `status` prints it, and `shot` captures the output at that size. Layout-dependent checks (portrait lock, narrow bars) must run at the matching size.

`--desktop` gives the nested Hyprland the tracked `config/general` gaps (in 4, out 6), border (2) and rounding (0), and loads `home/hypr/.config/hypr/config/general/frame.lua` from the bar's checkout (copied to `hypr/frame.lua` in the shadow dir), so the `ScreenFrame` global the bar dispatches to exists. Without it the shadow has Hyprland's default gaps and no repo globals. Use it with `spawn` whenever a check is about where tiled windows sit (reserved zones, the screen frame, rounding): `spawn <name>` twice gives two tiled foot windows. `spawn` waits up to 5 s for a new client to map and logs to `logs/spawn.log`; `down` stops every spawned client.

`<name>` is at most 8 characters (lowercase, digits, dashes): Hyprland's socket path under `/tmp/shadow-$UID-<name>` must fit 107 chars. With branches, `up` runs `owner-test-bar.sh build shadow-<name> <branch>...` (worktree, merge, `just check`; it never touches the live bar) and `down` removes that test bar again. Without branches it copies the main checkout's config, which may be behind `origin/main`; pass `main` to get `origin/main`. Either way the bar runs from a `cp -rL` copy in `~/.cache/dotfiles/shadow/<name>/qs`, so editing or removing the source does not change it; run `down` and `up` again to pick up changes. A layer `shot` that comes out near-uniform fails as blank (still animating in, or its content failed to load) and keeps the file. Shots default to `~/.cache/dotfiles/shadow/<name>/shots/`; Read them before `down`, which removes the shadow's whole folder (logs and shots included) unless given `--keep`. A failed `up` always keeps its logs.

`up` takes about 2.5 s (plus ~20 s for a branch build and its `just check`), and a running shadow costs about 460 MB PSS and under 1% of a core idle. Run `down` when done.

## What is isolated, and what is not

- Every process starts from `env -i` with a minimal environment: throwaway HOME `~/.cache/dotfiles/shadow/<name>/home` (wiped on each `up`, XDG config/state/cache/data under it), runtime dir `/tmp/shadow-$UID-<name>` (0700), a private session bus, no PipeWire socket (the bar's PipeWire connect error is expected and ignored), `HYPRLAND_NO_SD_VARS=1`, and `LIBSEAT_BACKEND=seatd` pointed at a socket that does not exist, so nothing asks logind for the seat or opens `/dev/input`. Clients get `WAYLAND_DISPLAY` as an absolute socket path inside the runtime dir and only the shadow's own `HYPRLAND_INSTANCE_SIGNATURE`; `keys`, `ipc` and `shot` refuse to run unless that socket exists there.
- The HOME is seeded with copies of the non-secret files the bar reads: the Quickshell and Hyprland state JSON (`theme.json`, `theme_options.json`, `bars.json`, `wallpaper.json`, ...), and the fontconfig file (never `weather.local.json` or the weather cache, which hold the owner's place: the shadow gets its own `weather.local.json` with fixed public coordinates and the name "Kokiri Forest", so it neither shows the owner's place nor looks one up by IP, and it fetches its own weather cache on first use, which needs network), plus the GoldenEye footage frames only when `SHADOW_GOLDENEYE_FRAMES=1` is set for `up` (without them the GoldenEye skins draw their fallback); the owner's user fonts are read in place. Bar actions that run `~/.config/hypr/scripts/*` find nothing there and do nothing, and `PATH` is a stub dir plus the system dirs, so `~/.local/bin` tools such as `keeptabs-status` are not run. `TMUX_TMPDIR` points at the runtime dir, so the tmux overview sees a private, empty tmux server rather than the owner's sessions.
- The system D-Bus is real: NetworkManager, BlueZ, UPower and power profiles are the machine's own. Network, Bluetooth or power actions in the shadow act on the real machine, so don't trigger them unless that is the point. The stubs below catch the command-line tools, but the bar's Quickshell services (Bluetooth, network, UPower) talk to the system bus directly and are not stubbed.
- The shadow shares the owner's PID namespace and hardware, so the commands below, which the bar can run and which act on the whole machine, are stubs in `~/.cache/dotfiles/shadow/<name>/shim/` (first on `PATH`). Each logs the call to `logs/shim.log` and exits 0; the read-only calls listed pass through to the real tool. Check `shim.log` to see what an action would have run.

  | Stubbed | Why | Passes through |
  | --- | --- | --- |
  | `pkill`, `killall`, `kill` | would signal the owner's processes (Screenshot's `pkill -x wf-recorder` stops their recording) | `kill -0` |
  | `systemctl`, `loginctl`, `shutdown`, `reboot`, `poweroff`, `halt` | power actions and the owner's services | `systemctl is-active`, `is-enabled`, `status`, `show`, `list-units` |
  | `brightnessctl`, `ddcutil` | the physical displays and keyboard backlight | `brightnessctl info`, `get`, `-l` |
  | `nmcli`, `bluetoothctl`, `rfkill`, `powerprofilesctl`, `busctl`, `udisksctl` | system-wide network, radio, power and disk state | `nmcli` `list`, `show`, `general`, `-g`; `busctl` `introspect`, `tree`, `list`, `get-property`, `status` |
  | `nm-connection-editor`, `blueman-manager` | GUIs that edit system network and Bluetooth state | nothing |
  | `sudo`, `pkexec`, `keyd` | privileged or system-wide | nothing |
  | `checkupdates`, `claude` | a database sync under `/tmp`, and the owner's Claude account | nothing |

  Not stubbed, because they only reach the shadow's own Wayland, session bus or HOME: `wl-copy`/`wl-paste`, `cliphist`, `notify-send`, `playerctl`, `hyprctl`, `grim`, `wf-recorder`, `wtype`, `zoxide`, `paru -Qua`, read-only `pgrep`/`pidof`/`ip`.
- The bar runs as `qs-shadow` (a symlink to `qs`), so `pgrep -x qs`, `pkill -x qs` (owner-test-bar's `launch`, `.claude/hooks/restart-qs-after-git.sh`) and `pgrep -af '^qs '` never match it, and restarting the owner's bar leaves the shadow alone.
- `down` kills each component's session (bar with its `voxtype` and other children, Hyprland, host, bus), unmounts the gvfs FUSE mount, then scans `/proc/*/environ` for the runtime dir, sweeps strays once, and fails listing any process still left.

## Host

The nested Hyprland runs inside headless labwc, started with an empty config in the shadow dir and `LABWC_UPDATE_ACTIVATION_ENV=0` (labwc does not count headless as nested, and would otherwise push the shadow's env into the owner's systemd and D-Bus activation environment). Aquamarine needs `xdg_wm_base` v6, which cage, sway and weston do not offer. Headless wlroots has no keyboard, and aquamarine stalls before listing its output until the host seat sends it an event, so `up` presses and releases Shift through a `wtype` virtual keyboard on the host socket until Hyprland lists the output.

labwc renders on the first non-NVIDIA render node (nested GBM allocation fails on NVIDIA's); set `SHADOW_RENDER_NODE=/dev/dri/renderD...` to override. The nested Hyprland gets a generated config with one output (1920x1080 unless `--size` says otherwise, set by the Hyprland monitor rule and filled by the nested window), Xwayland off, and no autostarts. Its output starts disabled and is enabled by a reload after the host's first configure, since aquamarine otherwise commits a buffer before acking it.

Logs: `~/.cache/dotfiles/shadow/<name>/logs/` (`qs.log`, `hypr.log`, `host.log`, `dbus.log`), gone after `down` unless `--keep`; Hyprland's full log is under the runtime dir while it runs.
