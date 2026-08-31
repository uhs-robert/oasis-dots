# dotfiles

Personal dotfiles managed with [GNU Stow](https://www.gnu.org/software/stow/). Packages live under `home/`.

## Full Install (Automated)

```bash
./install.sh        # full install (Arch only)
./install.sh -m     # minimal (skip optional components)
./install.sh -y     # auto-confirm all prompts
./uninstall.sh      # remove symlinks
```

Installs system packages, AUR packages, fonts, and dev tools, then stows dotfiles into `~/`. Prompts for optional components (greetd, Steam, Nvidia, dev runtimes).

Flags: `--no-aur`, `--no-cargo`, `--no-system-files`, `--no-services`.

## Partial Install (Manual Stow)

If you don't want to install the full dotfiles then you may also manually stow the individual packages that you want.

```bash
stow -d home <package>     # deploy a package
stow -d home -D <package>  # remove a package
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
```

## Root Yazi

The user Yazi keymap uses `~` and `$USER`, which resolve to `/root` when Yazi runs as root, so root gets a rewritten copy at `/root/.config/yazi/keymap.toml` rather than a symlink. Launch root Yazi with `yazi-root` (installed to `/usr/local/bin` by `install.sh`): it regenerates that copy from the current user keymap on every launch, so the two never drift. It finds the user config by resolving the `yazi.toml` symlink in `/root/.config/yazi`, so no username is configured anywhere. To refresh the copy without launching Yazi, run `yazi-root --sync-only` or `just sync-root-yazi`.

Plain `sudo yazi` stays in sync too, via a shim at `/usr/local/sbin/yazi` that runs the same regeneration before exec'ing the real binary. `sudo` ignores the caller's `PATH` in favour of `secure_path`, which starts with `/usr/local/sbin`, while a normal user's `PATH` has no `sbin` entries, so the shim applies to `sudo yazi` only, and your own `yazi` still runs `/usr/bin/yazi` directly.
