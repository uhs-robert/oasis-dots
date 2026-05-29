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
