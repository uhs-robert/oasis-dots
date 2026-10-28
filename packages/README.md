# Package manifests

These `.ini` files are the single list of what gets installed; adding a package means editing a manifest, not the installer. Plain lines are entries; `#` lines, blanks and `[SECTION]` headers are skipped. `read_pkgs` reads a whole file and `read_ini_section <file> <SECTION>` one section (`lib/common/packages.sh`).

- `arch.ini`, `arch-aur.ini`, `pipx.ini`, `luarocks.ini`, `devtools.ini`: package names. The comment lines of `arch.ini`'s `[MANUAL]` section print as post-install notes.
- `nvidia.ini`: driver packages, read by `install_nvidia` only after its prompt (`[USERSPACE]` plus `[DKMS]` or `[MODULE]`).
- `ssh-server.ini`: the Tailscale-only SSH server, read by `setup_tailnet_ssh` after its prompt.
- `snapper.ini`: snapper and snap-pac, read by `setup_snapper` after its prompt and only on a btrfs `/`.
- `stow.ini`: dotfile packages (`[CORE]` stowed automatically, `[OPTIONAL]` picked with fzf, `[SERVER]` instead of `[CORE]` under `--server`).
- `repos.ini`: git repositories to clone into `repos/`.

The `packages` check step (`lib/check/steps/packages.sh`) fails on a name listed in two manifests (`stow.ini` and `repos.ini` excepted, since they name directories and repos), on a `stow.ini` entry with no `home/` folder, and on a `home/` folder in neither `stow.ini` nor its `unstowed` list.
