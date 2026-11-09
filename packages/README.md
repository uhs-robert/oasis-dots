# Package manifests

These `.ini` files are the single list of what gets installed; adding a package means editing a manifest, not the installer. Plain lines are entries; `#` lines, blanks and `[SECTION]` headers are skipped. `read_pkgs` reads a whole file and `read_ini_section <file> <SECTION>` one section (`lib/common/packages.sh`).

- `arch.ini`, `arch-aur.ini`, `pipx.ini`, `luarocks.ini`, `devtools.ini`: package names. The comment lines of `arch.ini`'s `[MANUAL]` section print as post-install notes.
- `nvidia.ini`: driver packages, read by `install_nvidia` only after its prompt (`[USERSPACE]` plus `[DKMS]` or `[MODULE]`).
- `ssh-server.ini`: the Tailscale-only SSH server, read by `setup_tailnet_ssh` after its prompt.
- `agent-host.ini`: the nested-session packages (`labwc`, `hyprland`, `quickshell`, `grim`, `wtype`, `firefox`), read by `install_packages` only under `install.sh --agent-host`. They are also in `arch.ini` [DESKTOP], which `--server` skips, so the `packages` step lets this file repeat names from the others and checks it only for repeats within itself.
- `snapper.ini`: snapper and snap-pac, read by `setup_snapper` after its prompt and only on a btrfs `/`.
- `stow.ini`: dotfile packages (`[CORE]` stowed automatically, `[OPTIONAL]` picked with fzf, `[SERVER]` instead of `[CORE]` under `--server`).
- `repos.ini`: git repositories to clone into `repos/`.
- `artcraft.ini`: ArtCraft apps, one `storytold/<name>` GitHub repo each. `lib/install/artcraft-update` installs and updates them from their releases, because ArtCraft has no pacman repo or AUR package. Add a name here to get that app.

The `packages` check step (`lib/check/steps/packages.sh`) fails on a name listed in two manifests (`stow.ini` and `repos.ini` excepted, since they name directories and repos, and `agent-host.ini`, see above), on a `stow.ini` entry with no `home/` folder, and on a tracked `home/` folder that `stow.ini` does not list.
