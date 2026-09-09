# AGENTS.md

Guidance for coding agents working in this repository. `CLAUDE.md` is a pointer to this file; keep the content here.

## Overview

Personal Arch Linux dotfiles deployed with GNU Stow. Three deployment targets, each independent:

- `home/<package>/` — Stow packages symlinked into `~`. Directory layout under a package mirrors `$HOME` exactly (`home/kitty/.config/kitty/` becomes `~/.config/kitty/`).
- `system/` — files rsynced into `/` (`/etc`, `/opt`, `/usr/local/bin`). Not stowed; copied.
- `termux/` — standalone mobile SSH setup with its own `install.sh` and Stow packages. Independent of the desktop install; do not mix its packages with `home/`.

`.stowrc` pins `--dir=home --target=~`, so a bare `stow <package>` from the repo root works.

## Commands

```bash
just                  # list recipes
just check            # full validation (run before committing)
just lint             # shellcheck install.sh uninstall.sh lib/*.sh
just stow <pkg>       # symlink one package into ~
just restow <pkg>     # fix stale/broken links
just unstow <pkg>
just stow-core        # packages under [CORE] in packages/stow.ini
just stow-optional    # packages under [OPTIONAL]
just system-diff      # dry-run rsync of system/ into / (no sudo)
just system-apply     # apply system/ into / (sudo)
just sync-root-yazi   # regenerate root's Yazi keymap
./install.sh -m       # minimal install, skips AUR/rust/system files/services
```

`just check` runs `lib/check.sh`: shellcheck, `shfmt -i 2`, `stylua` on `home/hypr/.config/hypr`, duplicate-package detection, and trailing-whitespace scan. Optional tools are skipped when absent rather than failing. There is no single-test runner; the checks are all-or-nothing and report every failure in one pass.

Formatting scope is deliberately narrow — whitespace and stylua checks only cover `install.sh`, `uninstall.sh`, `justfile`, `lib/`, `packages/`, and `home/hypr/`. Everything else under `home/` is vendored or hand-maintained upstream config; do not reformat it.

## Installer architecture

`install.sh` is a thin orchestrator: parse flags, then call functions sourced from `lib/`. Each lib file owns one concern — `packages.sh` (manifest reading + pacman/pipx/luarocks), `arch.sh` (paru/AUR), `rust.sh`, `fonts.sh`, `stow.sh` (stowing + tmuxifier/neovim/root-symlink bootstrap), `services.sh` (greetd, keyd, Steam, Nvidia, voxtype, dev runtimes), `distro.sh`, `output.sh` (`info`/`warn`/`success`/`die`).

New install behavior belongs in the matching lib function, not inline in `install.sh`.

## Package manifests

`packages/*.ini` are the single source of truth for what gets installed. Plain lines are entries; `#`, blanks, and `[SECTION]` headers are skipped. `read_pkgs` reads a whole file, `read_ini_section <file> <SECTION>` reads one section.

- `arch.ini` / `arch-aur.ini` / `pipx.ini` / `luarocks.ini` / `devtools.ini` — package names.
- `stow.ini` — dotfile package names (`[CORE]` auto-stowed, `[OPTIONAL]` fzf-selected).
- `repos.ini` — git repositories to clone.

`lib/check-packages.sh` fails on a name appearing in two manifests, excluding `stow.ini` and `repos.ini` (those namespace directories and repos, not packages). Adding a package means editing the manifest, not the installer.

An `[MANUAL]` section's comment lines in `arch.ini` are printed as post-install notes.

## Hyprland config

`home/hypr/.config/hypr/` is Lua, not `hyprland.conf`. `hyprland.lua` is the entrypoint; it merges machine config (`config/machines/`) and loads the `hyprvim` plugin (Vim-modal window management with a which-key overlay). Subsystems live in `config/`, `keymaps/`, `extensions/`, `lib/`, `scripts/`, `theme/`. This tree is stylua-checked.

## Betterbird / tbkeys

`home/thunderbird/.config/tbkeys/*.js` are loaded in a fixed dependency order by `system/opt/betterbird/betterbird.cfg` — later modules may call earlier ones, never the reverse. `core.js` runs the previous load's teardown hooks and recreates `window.tk` from scratch. See README.md for the full module responsibility table; put new behavior in the module that owns that responsibility rather than reimplementing primitives.

`keys.json` and `quicktext.json` are tracked copies, not read from disk — after editing, paste into the add-on's options page. Restart Betterbird after editing any module.

## Yazi packages

Plugins are managed by `ya pkg`, with `home/yazi/.config/yazi/package.toml` as the manifest. Package-managed plugin directories are gitignored; only local plugins (`folder-rules.yazi`, `lazygit.yazi`) are tracked. Never hand-edit package metadata or copy upstream plugin files — run `ya pkg add/delete/upgrade` and commit the resulting `package.toml`.

## Submodules

`home/neovim/.config/nvim` and `home/qutebrowser/.config/qutebrowser/deserted-everything-css` are git submodules with SSH remotes. Changes there belong in the upstream repo; this repo only records the pointer.

## Gitignore

`.gitignore` is aggressive by design — credentials, AI assistant state, and generated config. `home/claude/**`, `home/gemini/**`, `home/codex/**` are ignored except for explicitly negated subpaths (agents, commands, skills, settings). Adding a new tracked file under those trees requires a matching `!` negation.

`CLAUDE.md`, `GEMINI.md`, and `AGENTS.md` are ignored everywhere except at the repository root — `!/CLAUDE.md` and `!/AGENTS.md` keep the top-level agent instructions tracked. A nested `AGENTS.md` under `home/` stays ignored.
