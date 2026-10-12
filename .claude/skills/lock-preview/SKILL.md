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

`show` starts the shadow `lockprev` when it is not running and reuses it otherwise; run `down` when finished. `--no-frames` uses a second shadow, `lockbare`, whose throwaway HOME has no GoldenEye footage frames, so the drawn GoldenEye shows. Shadows seed the frames only when `SHADOW_GOLDENEYE_FRAMES=1`, which `lockprev` sets. The bar comes from the main checkout, so to preview a branch use `shadow.sh up <name> <branch>` and drive it with `shadow.sh ipc <name> lock preview <skin>` and `shadow.sh shot <name> quickshell-lock-preview`.

In the preview: Esc and `q` close it, digits 1-5 switch fake phases (5 is the screensaver), Enter fails, Shift+Enter unlocks. The preview does not draw the `-- INSERT --` indicator; a real lock does. Lock input follows the vim model: NORMAL with nothing typed (h/j/k/l navigate menus, h/l do nothing on vertical lists), `i` or any other printable key enters INSERT, Esc on an empty buffer returns to NORMAL.
