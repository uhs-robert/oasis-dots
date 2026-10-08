# AGENTS.md

Guidance for coding agents working in this repository. `CLAUDE.md` is a pointer to this file; keep the content here.

## Overview

Personal Arch Linux dotfiles deployed with GNU Stow. Two deployment targets, each independent, plus extras that are never deployed:

- `home/<package>/` — Stow packages symlinked into `~`. Directory layout under a package mirrors `$HOME` exactly (`home/kitty/.config/kitty/` becomes `~/.config/kitty/`).
- `system/` — files rsynced into `/` (`/etc`, `/opt`, `/usr/local/bin`). Not stowed; copied.
- `extras/` — configs imported by hand into other apps (browser extensions). Never stowed or copied; keep anything Stow-shaped in `home/`.

`.stowrc` pins `--dir=home --target=~`, so a bare `stow <package>` from the repo root works.

## Commands

```bash
just                  # list recipes
just check            # full validation (run before committing)
just lint             # shellcheck install.sh uninstall.sh lib/*.sh demo/*.sh and the Quickshell audio importers
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

`just check` runs `lib/check.sh`: shellcheck and `shfmt -i 2` (installer, `lib/`, `demo/`, and the Quickshell audio importers `scripts/lib/*.sh`, `ff7-audio`, `goldeneye-audio`, `mgs2-audio`, `ocarina-audio`), `stylua` on `home/hypr/.config/hypr`, `luacheck` on the Hyprland and greetd Lua (`lib/check-lua.sh`; luacheck 1.2.0 crashes under Lua 5.5, so it falls back to `lua5.4`/`lua5.3`/`luajit` with LuaFileSystem for that interpreter, e.g. the `luacheck` or `lua54-filesystem` package), QML linting of the Quickshell config and greeter (`lib/check-qml.sh`: Qt 6 `qmllint` from `qt6-declarative` at `/usr/lib/qt6/bin`, since `/usr/bin/qmllint` is Qt 5's, run on a staged copy with the `qmldir` files Quickshell generates so singletons resolve, only for folders reached by folder imports from `shell.qml` as Quickshell registers them, failing when a file loaded by URL from an unreached folder instantiates, declares a property of, or reads a singleton among its siblings' types (#531); it fails on syntax errors, unknown types or imports, unknown or misspelled properties and names, type-incompatible assignments, writes to read-only properties, and duplicate or cyclic declarations, but not on style warnings, members read through untyped `parent`/`Loader.item`, or known gaps in Quickshell's type info; needs `jq`), duplicate-package detection, the lock skin index (`lib/check-lock-skins.sh`: `lock/skins/index.json` matches the skin files and audio importers, no skin imports `components/` or `services/`; needs `jq`), the Style token exports (`lib/check-style-exports.sh`: the generated property lines in `theme/Style.qml` match `theme/StyleSchema.js`; needs `python3`), tracked-symlink validation, trailing-whitespace scan, and conflict markers in tracked files (`lib/check-conflicts.sh`; a bare `=======` counts only in a file with a `<<<<<<<` line). After the `FAILED:` line it repeats the last 25 lines of each failing step's output, so a tail shows what broke. Optional tools are skipped when absent rather than failing. There is no single-test runner; the checks are all-or-nothing and report every failure in one pass.

Formatting scope is deliberately narrow — whitespace and stylua checks only cover `install.sh`, `uninstall.sh`, `justfile`, `lib/`, `packages/`, `home/hypr/`, and shfmt covers the Quickshell audio importers (`scripts/*-audio`, `scripts/lib/`). Everything else under `home/` is vendored or hand-maintained upstream config; do not reformat it.

## Installer architecture

`install.sh` is a thin orchestrator: parse flags, then call functions sourced from `lib/`. Each lib file owns one concern — `packages.sh` (manifest reading + pacman/pipx/luarocks), `arch.sh` (paru/AUR), `rust.sh`, `fonts.sh`, `stow.sh` (stowing + tmuxifier/neovim/root-symlink bootstrap), `repos.sh` (external repos in `repos/`), `services.sh` (greetd, keyd, Steam, Nvidia, voxtype, dev runtimes), `distro.sh`, `output.sh` (`info`/`warn`/`success`/`die`).

New install behavior belongs in the matching lib function, not inline in `install.sh`.

## Package manifests

`packages/*.ini` are the single source of truth for what gets installed. Plain lines are entries; `#`, blanks, and `[SECTION]` headers are skipped. `read_pkgs` reads a whole file, `read_ini_section <file> <SECTION>` reads one section.

- `arch.ini` / `arch-aur.ini` / `pipx.ini` / `luarocks.ini` / `devtools.ini` — package names.
- `nvidia.ini` — Nvidia driver packages, read by `install_nvidia` only after its prompt (`[USERSPACE]` plus `[DKMS]` or `[MODULE]`).
- `ssh-server.ini` — packages for the Tailscale-only SSH server, read by `setup_tailnet_ssh` only after its prompt.
- `stow.ini` — dotfile package names (`[CORE]` auto-stowed, `[OPTIONAL]` fzf-selected, `[SERVER]` used instead of `[CORE]` under `--server`).
- `repos.ini` — git repositories to clone.

`lib/check-packages.sh` fails on a name appearing in two manifests, excluding `stow.ini` and `repos.ini` (those namespace directories and repos, not packages). It also fails when a `stow.ini` entry has no `home/` dir, or a `home/` dir is in neither `stow.ini` nor its `unstowed` list. Adding a package means editing the manifest, not the installer.

An `[MANUAL]` section's comment lines in `arch.ini` are printed as post-install notes.

## Git config

`home/git/.config/git/config` is tracked and ends up at `~/.config/git/config`. It includes `identity`, a gitignored file holding only `[user]`; `setup_git_identity` writes it on install when absent and never overwrites one. Keep name and email out of the tracked config, the repo is public.

## Hyprland config

`home/hypr/.config/hypr/` is Lua, not `hyprland.conf`. `hyprland.lua` is the entrypoint; it merges machine config (`config/machines/`) and loads the `hyprvim` plugin (Vim-modal window management with a which-key overlay). Subsystems live in `config/`, `keymaps/`, `extensions/`, `lib/`, `scripts/`, `theme/`. This tree is stylua-checked.

Hyprland runs this Lua config, so drive it with the Lua API: `hyprctl keyword` fails, and `hyprctl dispatch` takes an `hl.dsp.*` expression (`hyprctl dispatch "hl.dsp.exec_cmd('qs -n')"`), not a dispatcher name like `exec` or `movecursor`. Use `hyprctl eval '...'` for anything else, including `hl.config({ ... })` in place of `keyword`.

User overrides live in two gitignored places, and tracked files must stay generic: `Config` values (hardware, default apps) in `config/machines/<hostname>.lua`, and everything built on the loaded library (binds, rules, launcher sessions) in `custom/`, whose `custom/init.lua` `hyprland.lua` requires last if present. Never auto-load other files in `custom/` from the Hyprland config. The one exception is the wallpaper rotator, a separate process that `custom/init.lua` cannot reach: it reads `custom/wallpaper.lua` and `custom/hyprpaper.conf` itself when present. Register binds through `lib/key/bind.lua` (`Bind.key`, `Bind.submap`), never raw `hl.bind` or `hl.define_submap`, so `Bind.unbind` can remove a key from one submap (hyprwm/Hyprland#15040). `Bind.unbind` and `Bind.submap` are public API for `custom/`; keep their signatures stable.

## Quickshell key conventions

Keep keys consistent across surfaces; new popups, pickers and skins follow these:

- Popups (`components/Popup.qml`; keys in `components/popup/PopupKeys.qml`): Tab/Shift+Tab step the top tabs, `[`/`]` step the bottom views; a popup with only one level answers both. Number keys pick a tab. Clock: Tab and `[`/`]` cycle timezones.
- Settings panes: `h` (and Esc, Tab) goes back to the sidebar and `l` or Enter goes in, like a file manager; a pane with nested views (Sessions) steps `h` and Esc up one view at a time and reaches the sidebar from its top view; a row's value steps with `l`/Space forward and Shift+`H`/`L` either way, so a section must leave plain `h` unused.
- Overviews (workspace and share picker): `s` selects a whole screen, Tab/Shift+Tab switch regular and special workspaces, `[`/`]` cycle windows, `f` toggles the view; in the share picker `r` opens the region selector and Esc there comes back.
- A popup action that opens a window (terminal, editor, file manager) launches it through `Popups.after_close(fn)`, never `Popups.close()` followed by a launch: a window that maps while the popup holds the keyboard ends up unfocused, because the layer closing hands focus back to the previous window.
- Lock and greeter input is a vim model owned by the shared router (`Lock.key`, `Greeter.key`): NORMAL while nothing is typed, where `h/j/k/l` navigate skin menus and `h`/`l` do nothing on vertical lists; `i` or any other printable key enters INSERT (`-- INSERT --` shows bottom-left); Esc on an empty buffer returns to NORMAL. The skin contract is in the Quickshell README.
- Full-screen interactive modes (pickers, zoom) follow `RegionSelector`: Quickshell owns keyboard and pointer, loads the skin cursor through `picker/cursors`, and has a `?` help box; never a Hyprland submap.
- Style tokens are declared once in `theme/StyleSchema.js` (type, default, doc) and each style's overrides live in `theme/styles/<name>.js`. Never hand-edit the `BEGIN generated` block in `Style.qml`; edit the schema and run `scripts/gen-style-exports` (in the Quickshell dir).
- Times use `TimeFormat` and `ClockSettings` (Settings > Clock); state paths use `theme/Paths.qml` and `lib/state.lua` instead of recomputing XDG dirs.

## Agent tooling

Claude Code hooks live in `.claude/settings.json` and `.claude/hooks/`. Repo skills: `test-bar` (put branches on the live bar, swap the Hyprland config when they touch it, `status`, `probe` IPC calls and `capture.sh` layer screenshots, then restore), `lock-preview` (skins on eDP-1) and `ship-batch` (merge through the global `merge-prs` skill, then check `main` and restart what changed). Worktrees have no `repos/`, so run `just check` in the real checkout before merging.

## Betterbird / tbkeys

`home/thunderbird/.config/tbkeys/*.js` are loaded in a fixed dependency order by `system/opt/betterbird/betterbird.cfg` — later modules may call earlier ones, never the reverse. `core.js` runs the previous load's teardown hooks and recreates `window.tk` from scratch. See `home/thunderbird/README.md` for the full module responsibility table; put new behavior in the module that owns that responsibility rather than reimplementing primitives.

`keys.json` and `quicktext.json` are tracked copies, not read from disk — after editing, paste into the add-on's options page. Restart Betterbird after editing any module.

## Yazi packages

Plugins are managed by `ya pkg`, with `home/yazi/.config/yazi/package.toml` as the manifest. Package-managed plugin directories are gitignored; only local plugins (`folder-rules.yazi`, `lazygit.yazi`) are tracked. Never hand-edit package metadata or copy upstream plugin files — run `ya pkg add/delete/upgrade` and commit the resulting `package.toml`.

## External repos

This repo has no submodules. `lib/repos.sh` sets up every repo in `repos.ini` (`owner/name` entries) plus the Neovim config under the gitignored `repos/` directory. By default each is cloned there over HTTPS. `$GITHUB_DIR` (default `~/Development`) and `$GITHUB_ORG` (default `uhs-robert`) can be overridden by the environment or an ignored `install.local` in the repo root (environment wins); `lib/distro.sh` reads it. With `./install.sh --dev`, or when `$GITHUB_DIR/<section>/<name>` already exists, the checkout lives under `$GITHUB_DIR` and `repos/<name>` is a symlink to it, so there is only ever one copy. `just update-repos` pulls the non-linked clones.

`lib/check-symlinks.sh` fails on a tracked symlink that dangles or points outside the repo; links into a `repos/` clone that is not set up yet are skipped.

Tracked files must reach external repos only through `repos/`: theme files are relative symlinks into `repos/oasis.nvim/extras`, and `hyprvim` and `deserted-everything-css` are symlinks into `repos/`. Runtime configs that cannot find the dotfiles checkout (shell rc files, Hyprland env) use `~/.local/share/dotfiles/repos`, which the installer links to `repos/`. Never hardcode `~/Development`.

`install_nvim_config` links `~/.config/nvim` to `repos/<name>` for `$NVIM_CONFIG_REPO` (default `uhs-robert/neovim`, also accepts a git URL), leaving any existing `~/.config/nvim` untouched.

## Gitignore

`.gitignore` is aggressive by design — credentials, AI assistant state, and generated config. `home/claude/**`, `home/gemini/**`, `home/codex/**` are ignored except for explicitly negated subpaths (agents, commands, skills, settings). Adding a new tracked file under those trees requires a matching `!` negation.

`CLAUDE.md`, `GEMINI.md`, and `AGENTS.md` are ignored everywhere except at the repository root — `!/CLAUDE.md` and `!/AGENTS.md` keep the top-level agent instructions tracked. A nested `AGENTS.md` under `home/` stays ignored.
