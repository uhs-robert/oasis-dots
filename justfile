# dotfiles/justfile

default:
    @just --list

system_excludes := "--exclude=/etc/tuigreet/config.toml --exclude=/etc/greetd/quickshell/ --exclude=/etc/greetd/hyprland.lua --exclude=/usr/local/bin/qs-greeter --exclude=/opt/ --exclude=/etc/ssh/"

# Show pending changes between system/ and / (dry run, no sudo)
system-diff:
    rsync -rlptv --omit-dir-times --chown=root:root --dry-run {{system_excludes}} system/ /
    @echo "Skipped installer-managed files: greeter via just greeter-sync --install; SSH server via just ssh-server; tuigreet config and Betterbird via install.sh"

# Copy system/ into / for real, e.g. /etc, /usr/local/bin (needs sudo)
system-apply:
    sudo rsync -rlptv --omit-dir-times --chown=root:root {{system_excludes}} system/ /
    @echo "Skipped installer-managed files: greeter via just greeter-sync --install; SSH server via just ssh-server; tuigreet config and Betterbird via install.sh"

# Symlink one package from home/ into ~
stow name:
    stow -d home -t ~ {{name}}
    @just _seed {{name}}

# Remove symlinks for one package from ~
unstow name:
    stow -d home -t ~ -D {{name}}

# Re-stow one package (fix stale/broken links)
restow name:
    stow -d home -t ~ -R {{name}}
    @just _seed {{name}}

# Symlink the CORE and OPTIONAL packages from packages/stow.ini
stow-all: stow-core stow-optional

# Remove symlinks for every package in home/
unstow-all:
    stow -d home -t ~ -D $(ls home)

# Symlink just the CORE packages from packages/stow.ini
stow-core:
    stow -d home -t ~ $(awk '/^\[CORE\]/{f=1;next} /^\[/{f=0} f && /^[^#[:space:]]/' packages/stow.ini)
    @just _seed $(awk '/^\[CORE\]/{f=1;next} /^\[/{f=0} f && /^[^#[:space:]]/' packages/stow.ini)

# Symlink just the OPTIONAL packages from packages/stow.ini
stow-optional:
    stow -d home -t ~ $(awk '/^\[OPTIONAL\]/{f=1;next} /^\[/{f=0} f && /^[^#[:space:]]/' packages/stow.ini)
    @just _seed $(awk '/^\[OPTIONAL\]/{f=1;next} /^\[/{f=0} f && /^[^#[:space:]]/' packages/stow.ini)

# Copy *.template.* defaults of the given packages into place when missing
_seed *pkgs:
    #!/usr/bin/env bash
    set -euo pipefail
    DOTFILES_DIR="$PWD"
    source lib/output.sh
    source lib/stow.sh
    seed_generated_defaults {{pkgs}}

# Run full dotfiles install (packages, stow, services); pass flags like --minimal
install *ARGS:
    ./install.sh {{ARGS}}

# Run uninstall script; pass through any flags
uninstall *ARGS:
    ./uninstall.sh {{ARGS}}

# Regenerate root's Yazi keymap from the current user keymap (needs sudo)
sync-root-yazi:
    ./system/usr/local/bin/yazi-root --sync-only

# Shellcheck install.sh, uninstall.sh, lib/*.sh, demo/*.sh, and the Quickshell audio importers
lint:
    shellcheck install.sh uninstall.sh lib/*.sh demo/*.sh
    shellcheck -x -P SCRIPTDIR home/quickshell/.config/quickshell/scripts/lib/*.sh home/quickshell/.config/quickshell/scripts/ff7-audio home/quickshell/.config/quickshell/scripts/goldeneye-audio home/quickshell/.config/quickshell/scripts/mgs2-audio home/quickshell/.config/quickshell/scripts/ocarina-audio

# Validate formatting, package manifests, and whitespace; run optional tooling when available
check:
    sh ./lib/check.sh

# Opt in to an SSH server reachable only over Tailscale, key login only (needs sudo)
ssh-server:
    #!/usr/bin/env bash
    set -euo pipefail
    DOTFILES_DIR="$PWD"
    for lib in output distro packages tailnet-ssh; do source "lib/$lib.sh"; done
    setup_tailnet_ssh

# Clone or link external repos into repos/ without a full install; pass --dev to use $GITHUB_DIR (default ~/Development)
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

# Stage the Quickshell greeter (lock skins, theme, fonts, your lock style) and print its sudo install commands; --install runs them, --from DIR stages from that Quickshell config dir
[positional-arguments]
greeter-sync *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    source lib/greeter.sh
    stage="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/greeter"
    args=("$@")
    from=""
    install=0
    for i in "${!args[@]}"; do
      [[ ${args[i]} == --install ]] && install=1
      if [[ ${args[i]} == --from ]]; then
        from=${args[i+1]:-}
        [[ -n $from ]] || { echo "greeter-sync: --from needs a directory" >&2; exit 1; }
        [[ -d $from/lock/skins && -f $from/theme/Theme.qml ]] || { echo "greeter-sync: $from is not a Quickshell config dir" >&2; exit 1; }
      fi
    done
    skin=$(stage_greeter "$stage" "$PWD" "$from") || { echo "greeter-sync: staging failed" >&2; exit 1; }
    echo "Staged greeter in $stage (skin: $skin)"
    if ((install)); then
      while read -r cmd; do echo "+ $cmd"; eval "$cmd"; done < <(greeter_install_cmds "$stage" "$PWD")
    else
      echo "Install with:"
      greeter_install_cmds "$stage" "$PWD" | sed 's/^/  /'
    fi

# Run the staged greeter in a window with a fake greetd: any password logs in except "wrong"; Esc quits
greeter-preview:
    #!/usr/bin/env bash
    set -euo pipefail
    source lib/greeter.sh
    stage="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/greeter"
    stage_greeter "$stage" "$PWD" >/dev/null
    env -u GREETD_SOCK -u QS_GREETER_STATE qs -p "$stage"

# Rehearse one showcase beat; `demo/showcase.sh list` prints the names
demo-beat name:
    demo/showcase.sh beat {{name}}

# Stage the desktop, film one clip per showcase beat, and cut them into the MP4
demo-record:
    demo/showcase.sh record
