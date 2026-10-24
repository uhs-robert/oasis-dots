---
name: lock-preview
description: Preview a lock-screen skin in a shadow bar and screenshot it, including the GoldenEye drawn version without the footage frames. Use when testing lock skins, the greeter look or lock input.
---

# Lock preview

Runs the preview inside a `shadow` bar (invisible nested Hyprland), so it is safe at any time and never touches the owner's screen or input.

```
.claude/skills/lock-preview/lock-preview.sh show <skin> [--no-frames]   # open it, wait for the layer, print the PNG path
.claude/skills/lock-preview/lock-preview.sh shot                       # another screenshot of the open preview
.claude/skills/lock-preview/lock-preview.sh keys <wtype args>          # e.g. `keys 3`, `keys -M shift -k Return -m shift`
.claude/skills/lock-preview/lock-preview.sh close                      # preview_close
.claude/skills/lock-preview/lock-preview.sh down                       # stop the shadows
```

Skins: `simple`, `crt`, `tie`, `ff7`, `mgs2`, `ocarina`, `goldeneye`. Read the PNG that `show` prints and delete it when done.

`show` starts the shadow `lockprev` when it is not running and reuses it otherwise; run `down` when finished. `--no-frames` uses a second shadow, `lockbare`, whose throwaway HOME has no GoldenEye footage frames, so the drawn GoldenEye shows. Shadows seed the frames only when `SHADOW_GOLDENEYE_FRAMES=1`, which `lockprev` sets. The bar comes from the checkout you run it in, so to preview a branch use `shadow.sh up <name> <branch>` and drive it with `shadow.sh ipc <name> lock preview <skin>` and `shadow.sh shot <name> quickshell-lock-preview`.

In the preview: Esc and `q` close it, digits 1-5 switch fake phases (5 is the screensaver), Enter fails, Shift+Enter unlocks. The preview does not draw the `-- INSERT --` indicator; a real lock does. Lock input follows the vim model: NORMAL with nothing typed (h/j/k/l navigate menus, h/l do nothing on vertical lists), `i` or any other printable key enters INSERT, Esc on an empty buffer returns to NORMAL.

## Greeter through the real-hardware path

`just greeter-preview` opens one `FloatingWindow`, which skips the per-screen `PanelWindow` path the login screen takes on hardware; that hid the G3b font-order bug (#1028). To exercise the real path:

```
.claude/skills/lock-preview/greeter-preview.sh [--scale 1.6] [--size 2560x1600] [--out PATH]
```

It stages the greeter from this checkout, brings up a shadow `greeter` at that size and scale (Hyprland rejects a scale that does not divide the size), and runs the staged greeter with `env -i`, a throwaway HOME and no `FONTCONFIG_FILE`, so only the bundled fonts can supply Barlow. `QS_GREETER_SCREENS=1` makes the preview build its screens instead of the window; it is opt-in because those windows are an exclusive-keyboard overlay. It prints the `greeter: fonts_ready=<bool> at screen build` log line and the `qs-greeter` layer PNG, then takes the shadow down. `fonts_ready=true` and a Barlow title is a pass; `false` or a wide fallback title is the G3b bug. Never set `QS_GREETER_SCREENS` outside a shadow.
