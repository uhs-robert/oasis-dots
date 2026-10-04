---
name: lock-preview
description: Preview a lock-screen skin on eDP-1, including the GoldenEye drawn version with the footage frames hidden. Use when testing lock skins, the greeter look or lock input.
---

# Lock preview

```
.claude/skills/lock-preview/lock-preview.sh show <skin> [--no-frames]
.claude/skills/lock-preview/lock-preview.sh close
.claude/skills/lock-preview/lock-preview.sh restore-frames
```

Skins: `simple`, `crt`, `tie`, `ff7`, `mgs2`, `ocarina`, `goldeneye`. `--no-frames` hides `~/.local/share/quickshell/goldeneye-frames` (links into `~/dotfiles-private`) so the drawn GoldenEye shows; always run `restore-frames` afterwards.

In the preview: Esc and `q` close it, digits 1-5 switch fake phases (5 is the screensaver), Enter fails, Shift+Enter unlocks. The preview does not draw the `-- INSERT --` indicator; a real lock does. Lock input follows the vim model: NORMAL with nothing typed (h/j/k/l navigate menus, h/l do nothing on vertical lists), `i` or any other printable key enters INSERT, Esc on an empty buffer returns to NORMAL.

Only open previews yourself when the owner says they are away; otherwise tell them which command to run.
