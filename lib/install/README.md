# Installer

`install.sh` sets up a machine from this repo: packages, stowed dotfiles, system files, services and external repos. `./install.sh -m` is a minimal install (no AUR, Rust, system files or services) and `./install.sh --server` a headless one. `uninstall.sh` reverses it. The `just` recipes run single steps (`just` lists them).

## Stowing

Each `home/<package>/` mirrors `$HOME` and is symlinked in with GNU Stow; `.stowrc` pins `--dir=home --target=~`, so a bare `stow <package>` from the repo root works for most packages. The exception is `NO_FOLD_PACKAGES` in `stow.sh` (`systemd`, `calendar`): systemd ignores drop-in and `.wants` directories that are symlinks, so these are stowed with `--no-folding`. Use `just stow`/`restow` for them, never a bare `stow`, and add any new package that ships `~/.config/systemd/user` units or drop-ins to that list. `just migrate-systemd [--dry-run]` (`migrate.sh`) repairs a machine stowed folded.

## External repos

This repo has no submodules. `repos.sh` sets up every repo in `packages/repos.ini` (`owner/name`) plus the Neovim config under the gitignored `repos/`, cloned over HTTPS. `$GITHUB_DIR` (default `~/Development`) and `$GITHUB_ORG` (default `uhs-robert`) come from the environment or an ignored `install.local` in the repo root (environment wins; `lib/common/distro.sh` reads it). With `./install.sh --dev`, or when `$GITHUB_DIR/<section>/<name>` already exists, the checkout lives under `$GITHUB_DIR` and `repos/<name>` links to it, so there is only one copy. `just update-repos` pulls the non-linked clones.

Tracked files reach external repos only through `repos/`: theme files are relative symlinks into `repos/oasis.nvim/extras`, and `hyprvim` and `deserted-everything-css` link into `repos/`. Runtime configs that cannot find the checkout (shell rc files, Hyprland env) use `~/.local/share/dotfiles/repos`, which the installer links to `repos/`. `install_nvim_config` links `~/.config/nvim` to `repos/<name>` for `$NVIM_CONFIG_REPO` (default `uhs-robert/neovim`, or a git URL) and leaves an existing `~/.config/nvim` alone. The `symlinks` check step fails on a tracked symlink that dangles or leaves the repo, skipping links into a `repos/` clone not set up yet.

## Code

- `install.sh` only parses flags and calls functions; new install behaviour goes in the matching function here, not inline.
- `load.sh` loads `lib/common/output.sh`, `distro.sh`, `packages.sh` and every `install/*.sh`. Callers (`install.sh`, `uninstall.sh`, the justfile) set `DOTFILES_DIR` and source only it, so a file here must only define at source time (`tests/load.sh` enforces silence). `require_arch` (sets `$DISTRO`, dies off Arch) is called by `install.sh` and `uninstall.sh` only.
- `lib/common/` holds what `uninstall.sh` and the justfile share: `packages.sh` (manifests, pacman/pipx/luarocks), `distro.sh`, `output.sh` (`info`/`warn`/`success`/`die`), `greeter-files.sh` (the Quickshell files the greeter stages). The check steps and the Quickshell status source `greeter-files.sh` or `greeter.sh` directly.
- One concern per file: `arch.sh` (paru, AUR), `rust.sh`, `fonts.sh`, `stow.sh` (stowing, `NO_FOLD_PACKAGES`, generated defaults), `dev-tools.sh` (runtimes, tmuxifier, git identity, Neovim), `system.sh` (system files, shell, keyd, power profiles, root symlinks), `hardware.sh` (Nvidia, xone, Steam), `snapper.sh`, `greeter.sh` (greetd, the Quickshell greeter, keyring unlock, `monitors.lua` from `greeter-monitors.lua`), `voice.sh` (voxtype, voxcmd's Firefox host and extension policy), `calendar.sh`, `repos.sh`, `migrate.sh` (one-time layout migrations), `tailnet-ssh.sh`.
- Tests: `tests/`. What gets installed is in [`packages/`](../../packages/README.md).
