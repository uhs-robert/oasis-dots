<p align="center">
  <img
    src="https://raw.githubusercontent.com/uhs-robert/oasis-dots/assets/logo.png"
    width="auto" height="128" alt="Oasis logo" />
</p>
<h1 align="center">oasis-dots</h1>
<p align="center">
  <a href="https://github.com/uhs-robert/oasis-dots/stargazers"><img src="https://img.shields.io/github/stars/uhs-robert/oasis-dots?colorA=192330&colorB=khaki&style=for-the-badge&cacheSeconds=4300" alt="Stargazers"></a>
  <a href="https://github.com/uhs-robert/oasis-dots/issues"><img src="https://img.shields.io/github/issues/uhs-robert/oasis-dots?colorA=192330&colorB=skyblue&style=for-the-badge&cacheSeconds=4300" alt="Issues"></a>
  <a href="https://github.com/uhs-robert/oasis-dots/graphs/contributors"><img src="https://img.shields.io/github/contributors/uhs-robert/oasis-dots?colorA=192330&colorB=8FD1C7&style=for-the-badge&cacheSeconds=4300" alt="Contributors"></a>
  <a href="https://github.com/uhs-robert/oasis-dots/network/members"><img src="https://img.shields.io/github/forks/uhs-robert/oasis-dots?colorA=192330&colorB=C799FF&style=for-the-badge&cacheSeconds=4300" alt="Forks"></a>
  <a href="https://github.com/uhs-robert/oasis-dots"><img src="https://img.shields.io/github/repo-size/uhs-robert/oasis-dots?colorA=192330&colorB=F4A261&style=for-the-badge&cacheSeconds=4300" alt="Repo size"></a>
</p>
<p align="center">Oasis-themed dotfiles for Arch Linux and Hyprland using Quickshell.</p>

## Desktop

An Arch Linux desktop on Hyprland, driven from the keyboard.

- [Hyprland](home/hypr/.config/hypr/README.md), configured in Lua, with [HyprVim](https://github.com/uhs-robert/hyprvim) for Vim-modal window management and which-key hints.
- A [Quickshell](home/quickshell/.config/quickshell/README.md) desktop shell: per-monitor bars, popups, notifications, pickers, a workspace overview, a Settings panel and the lock screen.
  - It comes in swappable styles, from a clean modern look to different gaming eras like NES, SNES, PS1 and PS2.
- [Oasis](https://github.com/uhs-robert/oasis.nvim) color themes across everything.
- A greetd login screen that reuses the lock screen's look, with tuigreet as a fallback.

> [!NOTE]
> Managed with [GNU Stow](https://www.gnu.org/software/stow/); packages live under `home/`.

<!-- Screenshots: add from the assets branch here. -->

## Full Install (Automated)

```bash
./install.sh        # full install (Arch only)
./install.sh -m     # minimal (skip optional components)
./install.sh --server # headless: shell/CLI/dev packages and configs only
./install.sh -y     # auto-confirm all prompts
./uninstall.sh      # remove symlinks
```

Installs system packages, AUR packages, fonts, and dev tools, then stows dotfiles into `~/`. Prompts for optional components (greetd, Steam, Nvidia, dev runtimes).

Flags: `--no-aur`, `--no-cargo`, `--no-system-files`, `--no-services`, `--dev`, `--server`.

`--server` is for headless machines: it installs the `[CORE] [SYSTEM] [CLI] [DEV]` sections of `packages/arch.ini` plus `[SHELL] [CLI]` from `packages/arch-aur.ini`, stows the `[SERVER]` list from `packages/stow.ini`, and skips fonts, Rust, greetd, and the desktop services.

## External Repos

Some configs live in their own repositories, listed in `packages/repos.ini`: Oasis themes (`oasis.nvim`), HyprVim, keeptabs, rob-bin, the qutebrowser site styles, and the Neovim config. The installer clones them into `repos/` inside this checkout (gitignored) and the dotfiles reference them from there, so nothing depends on where you keep your code.

```bash
./install.sh           # clone read-only copies into repos/ over HTTPS
./install.sh --dev     # clone into ~/Development over SSH and link repos/ to them, for editing
just repos             # set up repos/ only, without the full install (accepts --dev)
just update-repos      # pull the copies in repos/ (linked dev clones are skipped)
```

topgrade runs `just update-repos` as a custom command, so a normal `topgrade` keeps the repos current. HyprVim's own updater is turned off because its clone tracks `main` and is pulled the same way.

A repo that already exists under `~/Development/<section>/<name>` is always linked rather than cloned again. `~/.local/share/dotfiles/repos` points at `repos/` for shell and Hyprland configs that need a fixed path.

To use your own Neovim config, set `NVIM_CONFIG_REPO` to `owner/name` or a git URL before installing. An existing `~/.config/nvim` is never replaced.

```bash
NVIM_CONFIG_REPO=you/nvim ./install.sh
```

## Partial Install (Manual Stow)

If you don't want to install the full dotfiles then you may also manually stow the individual packages that you want. Theme files, HyprVim and the qutebrowser styles are symlinks into `repos/`, so run `just repos` first to set those up (see [External Repos](#external-repos)).

```bash
stow -d home <package>     # deploy a package
stow -d home -D <package>  # remove a package
```

The `git` package reads your `[user]` block from `~/.config/git/identity`, which is gitignored so each machine can use its own address. `./install.sh` prompts for it when missing; to write it by hand:

```bash
printf '[user]\n\tname = NAME\n\temail = EMAIL\n' > ~/.config/git/identity
```

## Yazi packages

Yazi plugins managed by `ya pkg` use `~/.config/yazi/package.toml` as the reproducible package manifest. Keep that file tracked in this repository and let `ya pkg` manage package state rather than manually editing package-managed plugin files.

```bash
ya pkg add <package>     # add a plugin and update package.toml
ya pkg delete <package>  # remove a plugin and update package.toml
ya pkg upgrade           # update installed packages and package.toml
ya pkg install           # restore packages recorded in package.toml
```

After changing Yazi packages, commit the resulting `home/yazi/.config/yazi/package.toml` change. Package-managed plugin directories under `home/yazi/.config/yazi/plugins/` are generated state and are ignored; only local plugins are tracked there. Do not hand-author package metadata or copy upstream plugin files as a substitute for running `ya pkg`.

## Justfile

Common tasks are wrapped in a `justfile` (run with [`just`](https://github.com/casey/just)). With `just`, you can just run:

```bash
just                  # list recipes
just stow <package>   # symlink one package
just unstow <package> # remove one package's symlinks
just install          # run install.sh
just uninstall        # run uninstall.sh
just sync-root-yazi   # regenerate root's Yazi keymap from the user's
just update-repos     # pull the external repos cloned into repos/
```

## Betterbird / tbkeys

Vim-style keybindings for Betterbird through the tbkeys add-on, with a Neovim compose bridge. See [home/thunderbird/README.md](home/thunderbird/README.md).

## Root Yazi

The user Yazi keymap uses `~` and `$USER`, which resolve to `/root` when Yazi runs as root, so root gets a rewritten copy at `/root/.config/yazi/keymap.toml` rather than a symlink. Launch root Yazi with `yazi-root` (installed to `/usr/local/bin` by `install.sh`): it regenerates that copy from the current user keymap on every launch, so the two never drift. It finds the user config by resolving the `yazi.toml` symlink in `/root/.config/yazi`, so no username is configured anywhere. To refresh the copy without launching Yazi, run `yazi-root --sync-only` or `just sync-root-yazi`.

Plain `sudo yazi` stays in sync too, via a shim at `/usr/local/sbin/yazi` that runs the same regeneration before exec'ing the real binary. `sudo` ignores the caller's `PATH` in favour of `secure_path`, which starts with `/usr/local/sbin`, while a normal user's `PATH` has no `sbin` entries, so the shim applies to `sudo yazi` only, and your own `yazi` still runs `/usr/bin/yazi` directly.

## Termux

For a standalone mobile SSH setup, see [termux/README.md](termux/README.md). It uses its own installer and Stow packages, independent of the desktop setup.
