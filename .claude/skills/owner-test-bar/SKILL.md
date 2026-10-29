---
name: owner-test-bar
description: Put unmerged Quickshell, Hyprland, voxcmd or voxtype/systemd-unit branches on the owner's real desktop so the OWNER can try them, then restore main. Not for agents' own checks, which go through the shadow skill; use this only when a branch needs the owner's live test before merging, including a voxcmd change the owner wants to say out loud.
---

# Owner test bar

## Scripts

Run from any worktree; never by hand, and never for an agent's own checks (use `shadow`).

- `.claude/skills/owner-test-bar/owner-test-bar.sh up <name> <branch>...`, then `probe "<ipc call>"` and read its output before telling the owner it is ready.
- `.claude/skills/owner-test-bar/owner-test-bar.sh try "<phrase>"...` on every voxcmd phrase before handing it to the owner; never hand over one that gives `no match`.
- A fix goes on the branch, then `rebuild <name>`. When done, `restore`, then `remove <name>`.
- One session owns the live test bar; `up`, `swap`, `rebuild` and `restore` refuse while another's claim is live; `--take` only with the owner's approval.

## Details

The owner tests every Quickshell change on their real bar before merging; this skill is how a branch gets there. It is for the owner to try, not for agents to test on. Do it with `owner-test-bar.sh` in this directory, never by hand: it merges the branches into a throwaway worktree, copies the gitignored assets (theme.json, FF7 audio) from the main checkout even when run from a worktree, runs `lib/check.sh --changed origin/main` (it never waits on the heavy-step lock), refuses to touch `qs` unless the lock reports `unlocked`, launches through Hyprland so `qs` does not inherit this shell's TMUX, and fails loudly on load errors.

```
.claude/skills/owner-test-bar/owner-test-bar.sh up <name> <branch>...   # build and swap in one step
.claude/skills/owner-test-bar/owner-test-bar.sh build <name> <branch>...
.claude/skills/owner-test-bar/owner-test-bar.sh swap <name>
.claude/skills/owner-test-bar/owner-test-bar.sh restore                  # back to the stowed bar on main
.claude/skills/owner-test-bar/owner-test-bar.sh rebuild <name>           # pick up new commits: restore if running, remove, up with the same branches
.claude/skills/owner-test-bar/owner-test-bar.sh remove <name>
.claude/skills/owner-test-bar/owner-test-bar.sh status                   # running qs, test bar HEAD vs its branch tips (or deleted branches), owner, hypr, voxcmd and voxtype
.claude/skills/owner-test-bar/owner-test-bar.sh probe "zoom start" ...   # IPC calls, then new log WARN/ERROR and quickshell layers
.claude/skills/owner-test-bar/owner-test-bar.sh try "focus workspace 3" ...  # dry-run each phrase (`explain` on a Rust voxcmd) with the live voxcmd; exit 1 on a no match
.claude/skills/owner-test-bar/capture.sh <namespace> [--pad N] [--reveal] [--screen NAME] [--out PATH]
```

When the branches touch `home/hypr`, `swap` also copies the gitignored Hyprland files (machine config, `custom/`, theme state) into the test worktree, re-points `~/.config/hypr` at it, reloads Hyprland and rolls back if `hyprctl configerrors` reports anything. It refuses to swap when this machine's profile under `config/machines/` did not make it into the copy, since Hyprland would otherwise reload with the monitors at automatic positions. It prints `hypr: swapped` or `hypr: unchanged`; `restore` (and `remove` of that bar) prints `hypr: restored`. All of it needs lock state `unlocked`.

When the branches touch `home/voxcmd`, `swap` also points every `~/.local/bin` script of the test build's voxcmd and the `~/.config/voxcmd` link at the test build, after linking the owner's private integrations (the extra symlinks in the live `integrations/` and `replacements.d/` from private dotfiles) into the test build's copy. It prints `voxcmd: test build <name>`, or `voxcmd: main` when the branches leave voxcmd alone. A test build also gets the debug log (`voxcmd: debug log at <path>`, `$XDG_RUNTIME_DIR/voxcmd/debug.log`), created if absent; `restore` deletes it only when the swap created it, so one the owner turned on stays. A branch that deletes `home/voxcmd/.local/bin/voxcmd` is a Rust-only build: `swap` first runs `cargo build --release --locked` on the bar's crate with `VOXCMD_GIT_HASH` set (before anything moves, so a compile error leaves the desktop on main and the build log at `<bar>.cargo.log`). Cargo builds into a staging dir (`target/stage`) and its JSON artifact record goes to `<bar>.cargo.json`, which names the built binary; `swap` copies that binary to `target/release/voxcmd.new` and renames it over `target/release/voxcmd`, and removes the `.cargo.json` on success or failure (the `.cargo.log` stays after a failure). Then it links `~/.local/bin/voxcmd` to the bar's `target/release/voxcmd` alongside the bar's other scripts and config. `restore` (and `remove` of that bar) removes the test links, restows voxcmd from the main checkout and relinks `~/.local/bin/voxcmd` to main's build (`~/.local/share/voxcmd-rs/bin/voxcmd`, made by `just voxcmd-build`; stow no longer makes that link, so restore warns when the build is missing), printing `voxcmd: main`; rerun `restore` if `status` reports voxcmd half swapped. Never relink voxcmd by hand: `stow` run from inside `home/` targets the repo itself.

When the branches touch `home/voxtype` (config or scripts) or `home/systemd`, `swap` also links the test build's `~/.config/voxtype`, its `voxtype-*` scripts and the units and drop-ins it adds or changes into `~`, runs `daemon-reload` and `try-restart voxtype`, and only then `enable --now`s each top-level unit the branch adds (derived from the diff, so a follower such as `voxtype-duck.service` comes up after voxtype runs the new config). It prints `voxtype: test build <name> (enabled <units>)` or `voxtype: unchanged`. `restore` (and `remove` of that bar) runs `disable --now` on the units the swap enabled, removes the test links, restows `voxtype` and `systemd` from the main checkout, reloads and restarts voxtype, printing `voxtype: main`; rerun it if `status` reports voxtype half swapped or restore reports it did not finish (a unit would not stop). Files and units the branch deletes are unlinked from main for the test (a deleted unit is disabled), and `restore` brings them back and re-enables (or, if it only ran, starts) the unit. Units whose definition changes, or that get a changed drop-in, are `try-restart`ed after the reload and again on restore. A change only to voxtype's tests does not trigger it, and restarting voxtype cuts off a recording in progress, so swap between dictations.

Test bars live in `~/.cache/dotfiles/test-bars/<name>`. Rules:

- One session owns the live test bar. `up`, `swap` and `rebuild` record the caller in `test-bars/.owner` (its `uds:` messaging address, session id, bar, branches and time; never a token), and `up`, `swap`, `rebuild` and `restore` refuse while another session's claim is live (its socket exists), naming the address to SendMessage. A claim whose socket is gone is reported as stale and taken over. Pass `--take` only when the owner approved taking the bar over. `restore`, and `remove` of the owned bar, clear the claim; `status` shows the owner and whether it is live.

- To add a fix to a test bar, push or commit it to the branch and run `rebuild <name>` (restores the stowed bar if needed, removes, then `up` with the recorded branches). Do not merge into a running test bar's worktree while another process rebases the branch; that raced once and left conflict markers on the live bar.
- Do not rely on hot-reload after merging into the test worktree; it kept stale code twice. `swap` again instead.
- `up` (and so `rebuild`) asks Codex to review each branch's open PR whose head has no Codex review, running one or asked for since the head commit, printing `codex: requested a review of #<n> (<branch>)`, so the review runs while the owner tests. Without `gh` or a PR it says nothing.
- After `up`, run `probe` with the feature's IPC entry and read its output before telling the owner it is ready. `probe` exits 1 on a new ERROR, a WARN repeated more than 5 times, or a load failure such as `X is not a type` (also checked by `verify`). It acts on the owner's live bar, so use it for that load check and for a test bar the owner is already using, not to explore the feature.
- `capture.sh` crops one layer of the live bar by namespace (the one under the cursor if several, or on `--screen NAME`); `--reveal` lifts `no_screen_share` for the shot so overlays show. Use it to see what the owner sees on a test bar they are using, not to run your own checks.
- Agents' own visual checks, IPC driving, key presses and screenshots never go through the live bar. Use the `shadow` skill (`shadow.sh up <name> <branch>` runs a branch in an invisible nested Hyprland), `shadow/smoke.sh` for the one-pass sheet of popup, OSD, which-key and region selector per style, and `lock-preview` for lock skins. No `qs ipc`, `wtype`, `grim` or `hyprctl` dispatch against the owner's session unless the owner asks for it.
- Reading the owner's live session needs no permission: `hyprctl -j` queries (clients, monitors, workspaces, activewindow, getoption), the bar's state JSON except what holds the owner's location, sessions or secrets (`weather.local.json`, the weather cache, `sessions.json`), and its logs. Anything that changes it needs the owner (`hyprctl dispatch`/`eval`/`reload`, `qs ipc` calls, sending keys, restarting the bar), except `probe` on a test bar the owner is using; agents' own driving goes to the shadow. Screenshots of the owner's real screen need the owner, since they show private content.
- Before telling the owner what to say, run every phrase through `try`; it uses the live voxcmd test build (the main install, and says so, when none is live). Never hand over a phrase that gives `no match`.
- Tell the owner exactly what to try, then wait for their verdict.
- When done: `restore`, then `remove`.
- After changing `owner-test-bar.sh`, run `tests/run.sh` (the ownership claim, branch status, voxcmd and the voxtype/unit lifecycle, against a temp cache dir and HOME with fake systemctl).
