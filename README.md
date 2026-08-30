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
```
