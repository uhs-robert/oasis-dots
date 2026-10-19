---
name: readme-captures
description: Script screenshots and short videos of the desktop for the oasis-dots README (the assets branch). Use when making or redoing README images or recordings.
---

# README captures

README images live on the `assets` branch under `docs/`, and the README links their raw URLs. Bar, popup and lock-screen shots can come from the `shadow` skill, which never shows a private window: `.claude/skills/shadow/shadow.sh up <name> [--size WxH]`, then `ipc <name> ...` and `shot <name> [<layer>]`. For a lock skin, `.claude/skills/lock-preview/lock-preview.sh show <skin>` does the same in its own shadow and prints the screenshot path. Use the live desktop only for shots that need real windows or the wallpaper, and only when the owner says they've stepped away.

- **Privacy:** never show real SSIDs or the real location. A shadow bar already shows a spoofed place (`shadow.sh` seeds its own `weather.local.json` with fixed public coordinates and the name "Kokiri Forest" and never copies the owner's). For a live-desktop shot, spoof it with latitude, longitude and `location_name` in `weather.local.json` in the Quickshell state dir (`~/.local/state/quickshell/`), and restore it afterwards.
- **Submaps:** Hyprland binds ignore `wtype` modifier combos. Enter submaps with `hyprctl eval 'hl.dispatch(hl.dsp.submap("Leader"))'` and reset with `hyprctl eval 'hl.dispatch(hl.dsp.submap("reset"))'`. Call HyprVim directly, e.g. `hyprctl eval 'require("hyprvim.vim").command.prompt()'`. Any `wtype` key drops Hyprland out of a submap entered that way, so submap binds can't be driven by simulated keys; ask the owner to press them if required.
- **Lock preview keys:** Esc and `q` close; digits 1-5 switch the fake phases; Enter fails; Shift+Enter unlocks. Go back through a menu's own "Back" item, never Esc, and type letter-only passwords without `q`. Ocarina: the first Enter only ignites the logo, a second opens file select. MGS2 menus use j/k.
- **Region selector:** wait for the `quickshell-region` layer, then about 1 s more, before `wtype`, or keys leak into the window below. Its zoom persists between opens, so reset it with `o` four times. The loupe follows the moving end, so end a selection on text.
- **Recording:** `wf-recorder -o <output> -r 30`, then convert to animated WebP with ffmpeg `libwebp` (fps 12, width 1000-1200, quality 40-55). Paired videos must match exactly; check frame counts with PIL.
- **Hero background:** nvim on README.md at `35G$` (topline 1), in a separate `tmux -L demo` session "Config" (windows yazi and zsh, automatic-rename off), inside `kitty --class kitty-tmux-config` on an empty workspace. The separate tmux server leaves the owner's sessions alone. `:e!` changes the view, so redo `gg35G$`.
