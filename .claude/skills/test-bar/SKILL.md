---
name: test-bar
description: Put one or more unmerged Quickshell branches on the owner's live bar for testing, then restore the normal bar. Use whenever a Quickshell branch needs a live test before merging.
---

# Test bar

The owner tests every Quickshell change on their real bar before merging. Do it with `test-bar.sh` in this directory, never by hand: it merges the branches into a throwaway worktree, copies the gitignored assets (theme.json, FF7 audio, weather.local.json), runs `just check`, refuses to touch `qs` unless the lock reports `unlocked`, launches through Hyprland so `qs` does not inherit this shell's TMUX, and fails loudly on load errors.

```
.claude/skills/test-bar/test-bar.sh up <name> <branch>...   # build and swap in one step
.claude/skills/test-bar/test-bar.sh build <name> <branch>...
.claude/skills/test-bar/test-bar.sh swap <name>
.claude/skills/test-bar/test-bar.sh restore                  # back to the stowed bar on main
.claude/skills/test-bar/test-bar.sh remove <name>
.claude/skills/test-bar/test-bar.sh status                   # running qs, test bar HEAD vs its branch tips, hypr swapped or not
.claude/skills/test-bar/test-bar.sh probe "zoom start" ...   # IPC calls, then new log WARN/ERROR and quickshell layers
.claude/skills/test-bar/capture.sh <namespace> [--pad N] [--reveal] [--out PATH]
```

When the branches touch `home/hypr`, `swap` also copies the gitignored Hyprland files (machine config, `custom/`, theme state) into the test worktree, re-points `~/.config/hypr` at it, reloads Hyprland and rolls back if `hyprctl configerrors` reports anything. It prints `hypr: swapped` or `hypr: unchanged`; `restore` (and `remove` of that bar) prints `hypr: restored`. All of it needs lock state `unlocked`.

Test bars live in `~/.cache/dotfiles/test-bars/<name>`. Rules:

- To add a fix to a running test bar, rebuild it (`remove`, then `up`). Do not merge into a running test bar's worktree while another process rebases the branch; that raced once and left conflict markers on the live bar.
- Do not rely on hot-reload after merging into the test worktree; it kept stale code twice. `swap` again instead.
- After `up`, run `probe` with the feature's IPC entry and read its output before telling the owner it is ready. `probe` exits 1 on a new ERROR or a WARN repeated more than 5 times.
- `capture.sh` crops one layer by namespace (the one under the cursor if several); `--reveal` lifts `no_screen_share` for the shot so overlays show. Use it to check overlays yourself when the owner allows self-tests.
- Tell the owner exactly what to try, then wait for their verdict. Visual self-tests (opening popups, simulated keys) are only allowed when the owner says they are away. Simulated `wtype` keys drop Hyprland out of any submap, so submap binds need the owner's hands.
- Screenshots: crop to the popup or bar with `grim -g` from `hyprctl layers -j` geometry, and delete them afterwards. Lock previews belong on eDP-1 (see the `lock-preview` skill).
- When done: `restore`, then `remove`.
