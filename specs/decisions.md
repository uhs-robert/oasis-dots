# Decisions log

Why AGENTS.md rules are the way they are. AGENTS.md keeps the rule and a one-clause reason; the history lives here and the rule links to its entry. Each entry has a date, the PR or commit, "chose X over Y because", and any footgun. Dates come from `git log -S` on the rule's text; an entry with no findable date says "undated, moved 2026-10-25". Entries are not spec requirements: this file has no front matter and no ids.

## Stow systemd and calendar unfolded

- Date: 2026-10-13. PR #815 (commit 31579a118), refs #811 and #812.
- Chose: stow `systemd` and `calendar` with `--no-folding`, through one `stow_packages` helper and a `NO_FOLD_PACKAGES` list that `do_stow` and every `just` stow, restow and unstow recipe use.
- Over: stowing them folded like every other package.
- Because: stow folds a directory that does not exist in `~` into one symlink, so `voxtype.service.d`, `graphical-session.target.wants` and `default.target.wants` were symlinks into the repo. systemd ignores drop-in and `.wants` directories that are symlinks: voxtype's `gpu.conf` never applied, voxtype was never enabled, and `systemctl --user enable` and `setup_voxtype` wrote generated files into the checkout (hence the ignore entries, which stay as guards).
- Migration: machines stowed earlier run `just migrate-systemd [--dry-run]` (`lib/install/migrate.sh`, idempotent). It unstows a folded tree, moves generated files (`gpu.conf`, wants links) from the repo into `~/.config`, stows again unfolded, runs `voxtype setup systemd` when the unit is missing or a repo symlink, and enables and starts voxtype. The installer runs only the unfold step, before stowing. A repo file whose target already exists is left alone and reported.
- Footgun: a bare `stow systemd` folds again. Any new package shipping `~/.config/systemd/user` units or drop-ins must be added to `NO_FOLD_PACKAGES`. `voxtype setup systemd` exits 0 even when its `systemctl` calls fail, so `setup_voxtype` checks `is-enabled` and `is-active` afterwards.

## Key each check step on its own definition

- Date: 2026-10-19. PR #1101 (commit 486532142).
- Chose: leave `scopes.py` out of the `all` lines of a pass-record key (`KEY_EXEMPT_ALL`) and hash each step's definition instead (`DEFINITION_FIELDS`: name, scope, command, needs, probe).
- Over: keying every step on `scopes.py`'s blob hash, as before.
- Because: `scopes.py` maps to scope `all`, so any edit to it, even an unrelated entry, invalidated every recorded pass, and the voice suites (11 to 26 minutes together) reran after each batch that touched the scope table. It still reaches `check-scope` and `check-cache` through its own column.
- Cost: the key version is 2 and byte-compatibility with the shell runner's keys was dropped, as agreed with the owner. Branches cut before the Python port run the shell runner, whose keys differ, so they do not share passes with this runner.
- Footgun: a new `Step` field that can change a pass must be listed in `keys.DEFINITION_FIELDS`, or in `NON_KEY_FIELDS` if it only affects scheduling; a guard test fails otherwise. `keys.py`, `runner.py`, `lock.sh` and `passed.*` stay `all` on purpose, since runner behaviour can change what passes.

## Unbind a key from one submap only

- Date: 2026-10-02. Commit d13657c64 (no PR found).
- Chose: `Bind` keeps each handle under its submap and unbinds those alone (`Bind.unbind`).
- Over: calling `hl.unbind` directly.
- Because: `hl.unbind` drops a key from the global map and every submap (hyprwm/Hyprland#15040). `Bind.unbind` removes the bind on Hyprland 0.57 and later and disables it on older releases.
- Footgun: a raw `hl.bind` or `hl.define_submap` has no handle, so `Bind.unbind` cannot reach it. Register through `home/hypr/.config/hypr/lib/key/bind.lua`. `Bind.unbind` and `Bind.submap` are public API for `custom/`.

## Launch windows from popups after the popup closes

- Date: 2026-10-08. PR #634 (commit b2af60c3d); the queue fix is commit 4bd8719cf.
- Chose: `Popups.after_close(fn)`, which closes the popup and queues `fn` until the `closelayer` event for the popup's namespace. A one-second fallback runs the queue if the event never arrives, and with no popup open `fn` runs at once.
- Over: `Popups.close()` followed by a launch, and per-caller workarounds (Updates tagged the topgrade window with a class, watched for it and refocused it).
- Because: the popup's layer still held the keyboard when the new window mapped, so Hyprland did not focus it, and when the layer finished closing Hyprland handed focus back to the window that had it before the popup opened. Launching once `closelayer>>quickshell-popup` arrived (about 0.2 s later) focused the window.
- Footgun: the one-second fallback keeps the action working but loses the focus guarantee. Updates keeps its `quickshell-upgrade` class because `home/hypr/.config/hypr/scripts/focus-topgrade.sh` finds the window by it. `Screenshot.run_after_close` is a separate fixed 350 ms wait so the popup is gone from the captured pixels, not a focus fix.

## Gitignore ignores by default

- Date: 2026-09-09. Commit fd33b05d3 (no PR found).
- Chose: a blanket ignore of credentials, AI assistant state and generated config, with explicit `!` negations for the tracked subpaths of `home/claude/**`, `home/gemini/**` and `home/codex/**`, and `!/CLAUDE.md` and `!/AGENTS.md` at the repository root only.
- Because (from the commit message): the blanket rule exists to keep AI state out of `home/claude`, so the root `CLAUDE.md` and `AGENTS.md` are unignored explicitly; a nested `AGENTS.md` under `home/` stays ignored. The commit records no alternative that was weighed.
- Footgun: a new tracked file under an ignored tree needs a matching `!` negation, or it silently never gets added.

## Lua defines actions; Hyprland is the registry

- Date: 2026-10-26. Branch `feat/hypr-act-list` (PR number added when it opens); builds on #1278 and #1281.
- Chose: define each action once in Lua with `Act.define` (`home/hypr/.config/hypr/lib/act.lua`), have `hypr-act list` ask the running Hyprland for the list, and check only the definitions' references headlessly (`registry` step, `home/hypr/tests/act_refs.lua`), discarding the output.
- Over: a hand-written `actions.json` plus per-tool bindings read by a Rust `oasis-djinn`, and over a generated, committed list with a drift check.
- Because: nothing at runtime read the manifest, so it had to be kept in step with the Lua by hand for no consumer, and the Rust runner needed its own build, install order and check step beside the Lua path keys already use. The owner always runs Hyprland, so a list that exists only while it runs costs nothing, and a committed list could drift from a `custom/` override anyway.
- Cost: with no Hyprland, `hypr-act list` prints nothing and exits 3, and no action can run. A key or the bar is dead then too.
- Footgun: machines that had `oasis-djinn` stowed run `stow -D oasis-djinn` before checking out this change, or `~/.config/oasis-djinn` dangles; then remove `~/.local/bin/oasis-djinn` and `~/.local/share/oasis-djinn-rs`.
