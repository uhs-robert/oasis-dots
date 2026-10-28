# AGENTS.md

Guidance for coding agents working in this repository. `CLAUDE.md` is a pointer to this file; keep the content here.

## Overview

Personal Arch Linux dotfiles deployed with GNU Stow. Two deployment targets, each independent, plus extras that are never deployed:

- `home/<package>/` — Stow packages symlinked into `~`. Directory layout under a package mirrors `$HOME` exactly (`home/kitty/.config/kitty/` becomes `~/.config/kitty/`).
- `system/` — files rsynced into `/` (`/etc`, `/opt`, `/usr/local/bin`). Not stowed; copied.
- `extras/` — configs imported by hand into other apps (browser extensions). Never stowed or copied; keep anything Stow-shaped in `home/`.

Use `just stow`/`restow`, not a bare `stow`, for `systemd` and `calendar` ([why](lib/install/README.md#stowing)). Tracked files reach external repos only through `repos/` (or `~/.local/share/dotfiles/repos` at runtime); never hardcode `~/Development` ([how](lib/install/README.md#external-repos)).

## Where to look

Before editing an area, read the `## Code` section of its README: it says which file does what and where to start. When you add, rename or remove a file there, update that map in the same PR.

| Area | README |
| --- | --- |
| Hyprland config, actions, keys | [`home/hypr/.config/hypr/README.md`](home/hypr/.config/hypr/README.md) |
| Quickshell (bar, popups, pickers, lock) | [`home/quickshell/.config/quickshell/README.md`](home/quickshell/.config/quickshell/README.md); its key conventions and structure rules apply to every Quickshell diff, and reviewers check against them |
| voxcmd | [`home/voxcmd/.config/voxcmd/README.md`](home/voxcmd/.config/voxcmd/README.md) |
| Installer, stow, external repos | [`lib/install/README.md`](lib/install/README.md) |
| Package manifests | [`packages/README.md`](packages/README.md) |
| The check runner | [`lib/check/README.md`](lib/check/README.md) |
| Betterbird / tbkeys | [`home/thunderbird/README.md`](home/thunderbird/README.md) |
| Yazi | [`home/yazi/.config/yazi/README.md`](home/yazi/.config/yazi/README.md) |

## Commands

```bash
just                  # list recipes
just check            # full validation (run before committing)
lib/check.sh --changed origin/main   # only the steps the changed files can affect, skipping those already passed for the same files
lib/check.sh --only voxcmd-click,voxcmd-rust   # just those steps; their passes count for the final --changed run
just lint             # shellcheck install.sh uninstall.sh, lib/check.sh, lib/{common,install,check}/**/*.sh, demo/*.sh and the Quickshell audio importers
just shaders          # rebuild every Quickshell .frag.qsb from its .frag (qsb); the shaders check step fails on a stale one
just stow <pkg>       # symlink one package into ~
just restow <pkg>     # fix stale/broken links
just unstow <pkg>
just stow-core        # packages under [CORE] in packages/stow.ini
just stow-optional    # packages under [OPTIONAL]
just system-diff      # dry-run rsync of system/ into / (no sudo); skips installer-managed files
just system-apply     # apply system/ into / (sudo); skips installer-managed files (greeter via `just greeter-sync --install`, SSH server via `just ssh-server`, tuigreet config and Betterbird via `install.sh`)
just sync-root-yazi   # regenerate root's Yazi keymap
just repos [--dev]    # set up repos/ without a full install
just update-repos     # pull non-linked clones in repos/
./install.sh -m       # minimal install, skips AUR/rust/system files/services
./install.sh --server # headless install, no desktop packages/configs/services
```

A new check step, or a path that should reach one, goes in the tables of `lib/check/scopes.py`; keep step docs in `lib/check/README.md`, not in `lib/check.sh` (an edit to the shim reruns every step).

A spec is `specs/core/<id>.md`, copied from `specs/core/TEMPLATE.md`; its front matter and any `.plans/` file's (the generic fields of the orchestrator skills plus `specs`, the list of spec ids it touches) are validated by the `specs` step against `specs/schema/` (`check-jsonschema`, from `packages/pipx.ini`; the step fails without it). Each requirement id (`- **BAR-03** ...`) is tagged in a test with `req: BAR-03` (a comment or a `vectors.tsv` note; several ids comma-separated) or marked `[gap: untested]` or `[gap: unmet]`; `lib/check/steps/specs.py --write` regenerates `specs/gaps.md`. Tooling tests and voxcmd goldens stay untagged.

Formatting scope is deliberately narrow — whitespace and stylua checks only cover `install.sh`, `uninstall.sh`, `justfile`, `lib/`, `packages/`, `home/hypr/`, and shfmt covers the Quickshell audio importers (`scripts/*-audio`, `scripts/lib/`) and the agent tooling's tracked shell scripts under `.claude/` and `home/claude/.claude/` (skills, hooks, `status.d`; written here, not vendored). Everything else under `home/` is vendored or hand-maintained upstream config; do not reformat it.

New install behaviour goes in the matching `lib/install/` function, and a new package in a `packages/` manifest, never inline in `install.sh`.

## Git config

`home/git/.config/git/config` is tracked and ends up at `~/.config/git/config`. It includes `identity`, a gitignored file holding only `[user]`; `setup_git_identity` writes it on install when absent and never overwrites one. Keep name and email out of the tracked config, the repo is public.

## Merging

Every PR merge goes through `.claude/skills/ship-batch/ship-batch.sh <n>...` (PRs in merge order), whether the owner said "merge N" or a standing approval covers it. `merge-prs.sh` is for `--check` only; a hook blocks it and the `gh` merge command otherwise. After a PR was merged on GitHub by hand, run `ship-batch.sh` with no arguments for the post-merge steps.

## The live desktop

These apply whenever you touch the running session, from any part of the repo:

- Hyprland runs a Lua config, so drive it with the Lua API: `hyprctl keyword` fails, and `hyprctl dispatch` takes an `hl.dsp.*` expression (`hyprctl dispatch "hl.dsp.exec_cmd('qs -n')"`), not a dispatcher name like `exec` or `movecursor`. Use `hyprctl eval '...'` for anything else, including `hl.config({ ... })` in place of `keyword`.
- After a re-login `HYPRLAND_INSTANCE_SIGNATURE` in long-lived shells is stale: the live instance is the newest socket under `$XDG_RUNTIME_DIR/hypr` that answers `hyprctl monitors`.
- Kill `qs` by PID rather than relying on `hyprctl`.
- Test voxcmd through `home/voxcmd/tests/sandbox.sh`, never against the live desktop. Regenerate the voxcmd goldens only with the owner's sign-off.

## Interaction conventions

How the owner expects anything interactive to behave, in Quickshell, voxcmd or a script. Agree a new surface's keys, look and first run with the owner before building it.

- Keyboard first. Every action has a key; the mouse is a shortcut, never the only way.
- vim semantics: `hjkl` move, Shift+`HJKL` the bigger step (month, year), `n`/`N` next and previous match, `gg`/`t` the start or today, `c` create, `o` open, `e` edit, `x` remove, Enter the main action, Esc or `h` back one level, `q` close.
- Bar markers stay small (a dot, a count, a few characters); the detail goes in the tooltip or the popup.
- A link opens in the default browser (`xdg-open`, Settings > Default apps) and the browser window is focused, not left behind.
- Public features work for anyone: never assume the owner's tools (rbw, Firefox, a particular terminal). Offer a guided setup for the common case and a config key for the rest.

## Docs

A README is for users first: what the feature does and how to use it, leading with what to do. It ends with a short `## Code` map for whoever changes it (which file does what, where to start), not a tour of every function. A trap or the reason behind a choice goes in a comment at the code it explains, never in a central log. `docs/` holds user guides that span features. `specs/` holds the roadmap and the specs; a feature's README links to its spec. None of these repeats a rule from this file; link to it.

`.plans/<topic>/<topic>.md` holds the tracker for work in progress (batch order, open points), with its plan drafts beside it; `.logs/<topic>/` holds its evidence (check output, review notes, PR bodies). Whoever owns the topic deletes both once it is merged or dropped, after moving anything durable into the repo in the last PR: a status into `specs/`, a decision's reason beside the code it explains. They exist in the main checkout only (both are gitignored, so worktrees do not see them); briefs give their absolute paths. An agent without a path finds the main checkout as the parent of `git rev-parse --path-format=absolute --git-common-dir`.

## Global agent files

Everything tracked under `home/claude/.claude/` (skills, agents, commands, hooks, `status.d`) is symlinked to `~/.claude/` and loaded in every project, so each line must hold in an unrelated repository (a Python web app, a Rust CLI). Project-specific guidance goes in this file or in `.claude/skills/`. Reviewers of any diff touching `home/claude/.claude/` flag every line that fails this test, whatever its subject.

## Gitignore

`.gitignore` ignores credentials, AI assistant state and generated config by default. `home/claude/**`, `home/gemini/**`, `home/codex/**` are ignored except for negated subpaths; a new tracked file there needs a `!` rule covering its path. `CLAUDE.md`, `GEMINI.md` and `AGENTS.md` are tracked only at the repository root.
