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
    @just _stow S {{name}}
    @just _seed {{name}}

# Remove symlinks for one package from ~
unstow name:
    @just _stow D {{name}}

# Re-stow one package (fix stale/broken links)
restow name:
    @just _stow R {{name}}
    @just _seed {{name}}

# Symlink the CORE and OPTIONAL packages from packages/stow.ini
stow-all: stow-core stow-optional

# Remove symlinks for every package in home/
unstow-all:
    @just _stow D $(ls home)

# Symlink just the CORE packages from packages/stow.ini
stow-core:
    @just _stow S $(awk '/^\[CORE\]/{f=1;next} /^\[/{f=0} f && /^[^#[:space:]]/' packages/stow.ini)
    @just _seed $(awk '/^\[CORE\]/{f=1;next} /^\[/{f=0} f && /^[^#[:space:]]/' packages/stow.ini)

# Symlink just the OPTIONAL packages from packages/stow.ini
stow-optional:
    @just _stow S $(awk '/^\[OPTIONAL\]/{f=1;next} /^\[/{f=0} f && /^[^#[:space:]]/' packages/stow.ini)
    @just _seed $(awk '/^\[OPTIONAL\]/{f=1;next} /^\[/{f=0} f && /^[^#[:space:]]/' packages/stow.ini)

# Stow one letter mode (S, D or R) on packages, unfolding those that must not fold (see lib/install/stow.sh)
_stow mode *pkgs:
    #!/usr/bin/env bash
    set -euo pipefail
    export DOTFILES_DIR="$PWD"
    source lib/install/load.sh
    [[ "{{mode}}" == D ]] || { migrate_quickshell_lock_assets; migrate_quickshell_state; migrate_quickshell_input; migrate_quickshell_weather; }
    stow_packages "-{{mode}}" {{pkgs}}

# One-time fix for a systemd tree folded into the repo (before #812's follow-up); idempotent, pass --dry-run to only report
migrate-systemd *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    export DOTFILES_DIR="$PWD"
    source lib/install/load.sh
    migrate_systemd {{ARGS}}

# Run every Quickshell migration (what install.sh and _stow run): link the lock assets, copy Quickshell's input.json to typing.json (kept, never overwritten), move weather.local.json from the checkout into the state dir (old copy deleted once the copy is verified), and move its per-checkout notifications/Claude usage state (by-shell) into the shared state dir; newest wins, so run it before and again after the bar restart (by-shell is deleted only by a run with no bar up: stop the bar, run, start it); MIGRATE_DRY_RUN=1 only reports
migrate-quickshell-state:
    #!/usr/bin/env bash
    set -euo pipefail
    export DOTFILES_DIR="$PWD"
    source lib/install/load.sh
    migrate_quickshell_lock_assets
    migrate_quickshell_state
    migrate_quickshell_input
    migrate_quickshell_weather

# Copy *.template.* defaults of the given packages into place when missing
_seed *pkgs:
    #!/usr/bin/env bash
    set -euo pipefail
    export DOTFILES_DIR="$PWD"
    source lib/install/load.sh
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

# Shellcheck install.sh, uninstall.sh, lib/check.sh, lib/{common,install,check}/**/*.sh, demo/*.sh, and the Quickshell audio importers
lint:
    shellcheck install.sh uninstall.sh lib/check.sh lib/common/*.sh lib/install/*.sh lib/install/tests/*.sh lib/check/*.sh lib/check/steps/*.sh lib/check/tests/*.sh demo/*.sh
    shellcheck -x -P SCRIPTDIR home/quickshell/.config/quickshell/scripts/lib/*.sh home/quickshell/.config/quickshell/scripts/ff7-audio home/quickshell/.config/quickshell/scripts/goldeneye-audio home/quickshell/.config/quickshell/scripts/mgs2-audio home/quickshell/.config/quickshell/scripts/ocarina-audio

# Rebuild every Quickshell .frag.qsb from its .frag (qt6-shadertools); `just check` fails when one is stale
shaders:
    sh lib/check/steps/shaders.sh --write

# Validate formatting, package manifests, and whitespace; run optional tooling when available
check:
    sh ./lib/check.sh

# Time how long voxcmd takes to route the benchmark phrases in the sandbox (--runs N, --live, --all); see home/voxcmd/tests/bench.sh
voxcmd-bench *ARGS:
    home/voxcmd/tests/bench.sh {{ARGS}}

# Build the Rust voxcmd and install it as ~/.local/bin/voxcmd-rs, beside the stowed bash voxcmd that stays live until the swap (voxcmd-port 3.2)
voxcmd-build:
    #!/usr/bin/env bash
    set -euo pipefail
    root="${XDG_DATA_HOME:-$HOME/.local/share}/voxcmd-rs"
    VOXCMD_GIT_HASH="$(git describe --always --dirty --abbrev=9 --exclude='*')" cargo install --path home/voxcmd --locked --root "$root"
    mkdir -p "$HOME/.local/bin"
    ln -sf "$root/bin/voxcmd" "$HOME/.local/bin/voxcmd-rs"
    "$HOME/.local/bin/voxcmd-rs" --version

# Build `oasis-djinn` (home/oasis-djinn) and link it as ~/.local/bin/oasis-djinn; the installer does the same after stowing
djinn-build:
    #!/usr/bin/env bash
    set -euo pipefail
    export DOTFILES_DIR="$PWD"
    source lib/install/load.sh
    build_djinn

# Rewrite the committed integration JSON Schema from the Rust types; it fails until `voxcmd integrations schema` exists (voxcmd-port 2.6)
voxcmd-schema:
    #!/usr/bin/env bash
    set -euo pipefail
    schema=home/voxcmd/.local/share/voxcmd/integration.schema.json
    tmp="$(mktemp)"
    trap 'rm -f "$tmp"' EXIT
    cargo run --quiet --release --locked --manifest-path home/voxcmd/Cargo.toml -- integrations schema >"$tmp"
    mv "$tmp" "$schema"

# The Rust crate's tests, then the voxcmd suites against this checkout's Rust build (they fail until the router lands in it, voxcmd-port 2.2)
voxcmd-test:
    #!/usr/bin/env bash
    set -euo pipefail
    cargo test --locked --manifest-path home/voxcmd/Cargo.toml
    failed=()
    for suite in run-phrases run run-calendar run-wake run-firefox-extension; do
        VOXCMD_BIN=rs "home/voxcmd/tests/$suite.sh" || failed+=("$suite")
    done
    [ "${#failed[@]}" = 0 ] || { echo "suites failed under VOXCMD_BIN=rs: ${failed[*]}" >&2; exit 1; }

# Sample the running wake word listener's memory and CPU for N minutes; run it on an idle machine
voxcmd-wake-sample minutes="60":
    home/voxcmd/tests/wake-sample.sh {{minutes}}

# Sign the voxcmd Firefox extension as unlisted on addons.mozilla.org, into extras/voxcmd-firefox.xpi; the API key is read from rbw
sign-firefox-extension:
    #!/usr/bin/env bash
    set -euo pipefail
    entry="Firefox AMO API Key"
    # Passed in the environment, not as arguments, so the secret never shows in the process list.
    # The issuer is the entry's username, or the first line of its notes when it was stored there.
    WEB_EXT_API_KEY=$(rbw get --field username "$entry")
    [[ -n $WEB_EXT_API_KEY ]] || WEB_EXT_API_KEY=$(rbw get --field notes "$entry" | head -n 1)
    [[ $WEB_EXT_API_KEY =~ ^user:[0-9]+:[0-9]+$ ]] || { echo "no JWT issuer (user:<numbers>:<numbers>, from addons.mozilla.org/developers/addon/api/key/) in the username or notes of rbw's \"$entry\"" >&2; exit 1; }
    WEB_EXT_API_SECRET=$(rbw get "$entry")
    export WEB_EXT_API_KEY WEB_EXT_API_SECRET
    artifacts=$(mktemp -d)
    trap 'rm -rf "$artifacts"' EXIT
    npx --yes web-ext@10.7.0 sign --channel=unlisted --source-dir extras/voxcmd-firefox --artifacts-dir "$artifacts"
    signed=$(find "$artifacts" -name '*.xpi' -print -quit)
    [[ -n $signed ]] || { echo "web-ext returned no signed .xpi" >&2; exit 1; }
    cp "$signed" extras/voxcmd-firefox.xpi
    echo "signed: extras/voxcmd-firefox.xpi"

# Let the greetd login unlock the GNOME keyring (needs sudo); greeter-sync --install and the installer also run it
greeter-keyring:
    #!/usr/bin/env bash
    set -euo pipefail
    export DOTFILES_DIR="$PWD"
    source lib/install/load.sh
    enable_greetd_keyring_unlock

# Install the signed voxcmd extension through a Firefox policy (needs sudo) and register its host, so one command sets everything up
firefox-extension:
    #!/usr/bin/env bash
    set -euo pipefail
    export DOTFILES_DIR="$PWD"
    source lib/install/load.sh
    register_firefox_host
    install_firefox_extension_policy

# Register voxcmd's Firefox native-messaging host (needs the voxcmd package stowed); load extras/voxcmd-firefox in Firefox afterwards
firefox-host:
    #!/usr/bin/env bash
    set -euo pipefail
    export DOTFILES_DIR="$PWD"
    source lib/install/load.sh
    register_firefox_host

# Tune pacman.conf and makepkg, enable the paccache timer (asks first; needs sudo)
pacman-tweaks:
    #!/usr/bin/env bash
    set -euo pipefail
    export DOTFILES_DIR="$PWD"
    source lib/install/load.sh
    setup_pacman_tweaks

# Opt in to an SSH server reachable only over Tailscale, key login only (needs sudo)
ssh-server:
    #!/usr/bin/env bash
    set -euo pipefail
    export DOTFILES_DIR="$PWD"
    source lib/install/load.sh
    setup_tailnet_ssh

# Clone or link external repos into repos/ without a full install; pass --dev to use $GITHUB_DIR (default ~/Development)
repos *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    export DOTFILES_DIR="$PWD"
    source lib/install/load.sh
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
    export DOTFILES_DIR="$PWD"
    source lib/install/load.sh
    stage="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/greeter"
    args=("$@")
    from=""
    install=0
    for i in "${!args[@]}"; do
      [[ ${args[i]} == --install ]] && install=1
      if [[ ${args[i]} == --from ]]; then
        from=${args[i+1]:-}
        [[ -n $from ]] || { echo "greeter-sync: --from needs a directory" >&2; exit 1; }
        for entry in "${GREETER_QS_FILES[@]}"; do
          [[ $entry == *'?' ]] && continue
          compgen -G "$from/${entry%/}" >/dev/null || { echo "greeter-sync: $from is not a Quickshell config dir: no $entry" >&2; exit 1; }
        done
      fi
    done
    skin=$(stage_greeter "$stage" "$PWD" "$from") || { echo "greeter-sync: staging failed" >&2; exit 1; }
    echo "Staged greeter in $stage (skin: $skin)"
    if ((install)); then
      while read -r cmd; do echo "+ $cmd"; eval "$cmd"; done < <(greeter_install_cmds "$stage" "$PWD")
      enable_greetd_keyring_unlock
    else
      echo "Install with:"
      greeter_install_cmds "$stage" "$PWD" | sed 's/^/  /'
    fi

# Run the staged greeter in a window with a fake greetd: any password logs in except "wrong"; Esc quits
greeter-preview:
    #!/usr/bin/env bash
    set -euo pipefail
    export DOTFILES_DIR="$PWD"
    source lib/install/load.sh
    stage="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/greeter"
    stage_greeter "$stage" "$PWD" >/dev/null
    env -u GREETD_SOCK -u QS_GREETER_STATE qs -p "$stage"

# Rehearse one showcase beat; `demo/showcase.sh list` prints the names
demo-beat name:
    demo/showcase.sh beat {{name}}

# Stage the desktop, film one clip per showcase beat, and cut them into the MP4
demo-record:
    demo/showcase.sh record
