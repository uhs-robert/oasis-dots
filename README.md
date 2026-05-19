# dotfiles

Personal dotfiles managed with [GNU Stow](https://www.gnu.org/software/stow/). Packages live under `home/`.

## Install

> [!WARNING]
> This install script is still under development and has not been tested on a live system.
>
> Use the install script at your own risk, please wait till this banner is removed.
>
> Use the [Manual Stow](#manual-stow) instead for a tried/true install method.

```bash
./install.sh        # full install (Fedora or Arch)
./install.sh -m     # minimal (skip optional components)
./install.sh -y     # auto-confirm all prompts
./uninstall.sh      # remove symlinks
```

Installs system packages, Flatpak/Cargo/AUR packages, fonts, and dev tools, then stows dotfiles into `~/`. Prompts for optional components (greetd, Steam, Nvidia, dev runtimes).

Flags: `--no-copr`, `--no-aur`, `--no-flatpak`, `--no-cargo`, `--no-system-files`, `--no-services`.

## Manual Stow

```bash
stow -d home <package>     # deploy a package
stow -d home -D <package>  # remove a package
```
