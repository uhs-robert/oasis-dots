# dotfiles/justfile

default:
    @just --list

# Show pending changes between system/ and / (dry run, no sudo)
system-diff:
    rsync -rlptv --omit-dir-times --chown=root:root --dry-run system/ /

# Copy system/ into / for real, e.g. /etc, /usr/local/bin (needs sudo)
system-apply:
    sudo rsync -rlptv --omit-dir-times --chown=root:root system/ /

# Symlink one package from home/ into ~
stow name:
    stow -d home -t ~ {{name}}

# Remove symlinks for one package from ~
unstow name:
    stow -d home -t ~ -D {{name}}

# Re-stow one package (fix stale/broken links)
restow name:
    stow -d home -t ~ -R {{name}}

# Symlink every package in home/ into ~
stow-all:
    stow -d home -t ~ $(ls home)

# Remove symlinks for every package in home/
unstow-all:
    stow -d home -t ~ -D $(ls home)

# Symlink just the CORE packages from packages/stow.ini
stow-core:
    stow -d home -t ~ $(awk '/^\[CORE\]/{f=1;next} /^\[/{f=0} f && /^[^#[:space:]]/' packages/stow.ini)

# Symlink just the OPTIONAL packages from packages/stow.ini
stow-optional:
    stow -d home -t ~ $(awk '/^\[OPTIONAL\]/{f=1;next} /^\[/{f=0} f && /^[^#[:space:]]/' packages/stow.ini)

# Run full dotfiles install (packages, stow, services); pass flags like --minimal
install *ARGS:
    ./install.sh {{ARGS}}

# Run uninstall script; pass through any flags
uninstall *ARGS:
    ./uninstall.sh {{ARGS}}

# Regenerate root's Yazi keymap from the current user keymap (needs sudo)
sync-root-yazi:
    ./system/usr/local/bin/yazi-root --sync-only

# Shellcheck install.sh, uninstall.sh, and lib/*.sh
lint:
    shellcheck install.sh uninstall.sh lib/*.sh

# Validate formatting, package manifests, and whitespace; run optional tooling when available
check:
    sh ./lib/check.sh

# Clone or link external repos into repos/ without a full install; pass --dev to use ~/Development
repos *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    DOTFILES_DIR="$PWD"
    for lib in output distro packages repos stow; do source "lib/$lib.sh"; done
    OPT_DEV=0
    [[ " {{ARGS}} " == *" --dev "* ]] && OPT_DEV=1
    clone_repos
    install_nvim_config

# Pull repos/ checkouts cloned for this machine; linked dev checkouts are skipped
update-repos:
    #!/usr/bin/env bash
    for dir in repos/*/; do
      [[ -L "${dir%/}" ]] && continue
      echo "==> ${dir%/}"
      if git -C "$dir" symbolic-ref -q HEAD >/dev/null; then
        git -C "$dir" pull --ff-only
      else
        echo "skip: not on a branch (pinned to $(git -C "$dir" describe --tags --always))"
      fi
    done
