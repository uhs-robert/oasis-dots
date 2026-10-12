---
name: test-bar
description: Put one or more unmerged Quickshell branches on the owner's live bar so the owner can try them, then restore the normal bar. Use when a Quickshell branch needs the owner's live test before merging; agents' own visual checks use the shadow skill.
---

# Test bar

The owner tests every Quickshell change on their real bar before merging; test-bar is how a branch gets there. It is for the owner to try, not for agents to test on. Do it with `test-bar.sh` in this directory, never by hand: it merges the branches into a throwaway worktree, copies the gitignored assets (theme.json, FF7 audio, weather.local.json) from the main checkout even when run from a worktree, runs `just check`, refuses to touch `qs` unless the lock reports `unlocked`, launches through Hyprland so `qs` does not inherit this shell's TMUX, and fails loudly on load errors.

```
.claude/skills/test-bar/test-bar.sh up <name> <branch>...   # build and swap in one step
.claude/skills/test-bar/test-bar.sh build <name> <branch>...
.claude/skills/test-bar/test-bar.sh swap <name>
.claude/skills/test-bar/test-bar.sh restore                  # back to the stowed bar on main
.claude/skills/test-bar/test-bar.sh rebuild <name>           # pick up new commits: restore if running, remove, up with the same branches
.claude/skills/test-bar/test-bar.sh remove <name>
.claude/skills/test-bar/test-bar.sh status                   # running qs, test bar HEAD vs its branch tips, hypr swapped or not
.claude/skills/test-bar/test-bar.sh probe "zoom start" ...   # IPC calls, then new log WARN/ERROR and quickshell layers
.claude/skills/test-bar/capture.sh <namespace> [--pad N] [--reveal] [--screen NAME] [--out PATH]
```

When the branches touch `home/hypr`, `swap` also copies the gitignored Hyprland files (machine config, `custom/`, theme state) into the test worktree, re-points `~/.config/hypr` at it, reloads Hyprland and rolls back if `hyprctl configerrors` reports anything. It refuses to swap when this machine's profile under `config/machines/` did not make it into the copy, since Hyprland would otherwise reload with the monitors at automatic positions. It prints `hypr: swapped` or `hypr: unchanged`; `restore` (and `remove` of that bar) prints `hypr: restored`. All of it needs lock state `unlocked`.

Test bars live in `~/.cache/dotfiles/test-bars/<name>`. Rules:

- To add a fix to a test bar, push or commit it to the branch and run `rebuild <name>` (restores the stowed bar if needed, removes, then `up` with the recorded branches). Do not merge into a running test bar's worktree while another process rebases the branch; that raced once and left conflict markers on the live bar.
- Do not rely on hot-reload after merging into the test worktree; it kept stale code twice. `swap` again instead.
- After `up`, run `probe` with the feature's IPC entry and read its output before telling the owner it is ready. `probe` exits 1 on a new ERROR, a WARN repeated more than 5 times, or a load failure such as `X is not a type` (also checked by `verify`). It acts on the owner's live bar, so use it for that load check and for a test bar the owner is already using, not to explore the feature.
- `capture.sh` crops one layer of the live bar by namespace (the one under the cursor if several, or on `--screen NAME`); `--reveal` lifts `no_screen_share` for the shot so overlays show. Use it to see what the owner sees on a test bar they are using, not to run your own checks.
- Agents' own visual checks, IPC driving, key presses and screenshots never go through the live bar. Use the `shadow` skill (`shadow.sh up <name> <branch>` runs a branch in an invisible nested Hyprland), `shadow/smoke.sh` for the one-pass sheet of popup, OSD, which-key and region selector per style, and `lock-preview` for lock skins. No `qs ipc`, `wtype`, `grim` or `hyprctl` dispatch against the owner's session unless the owner asks for it.
- Tell the owner exactly what to try, then wait for their verdict.
- When done: `restore`, then `remove`.
