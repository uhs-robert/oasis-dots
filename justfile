# dotfiles/justfile

default:
    @just --list

system_excludes := "--exclude=/etc/tuigreet/config.toml --exclude=/etc/greetd/quickshell/ --exclude=/etc/greetd/hyprland.lua --exclude=/usr/local/bin/qs-greeter --exclude=/opt/ --exclude=/usr/lib/firefox/ --exclude=/etc/ssh/"

# Show pending changes between system/ and / (dry run, no sudo)
system-diff:
    rsync -rlptv --omit-dir-times --chown=root:root --dry-run {{system_excludes}} system/ /
    @echo "Skipped installer-managed files: greeter via just greeter-sync --install; SSH server via just ssh-server; tuigreet config, Betterbird and the Firefox autoconfig via install.sh"

# Copy system/ into / for real, e.g. /etc, /usr/local/bin (needs sudo)
system-apply:
    sudo rsync -rlptv --omit-dir-times --chown=root:root {{system_excludes}} system/ /
    sudo systemctl daemon-reload
    @echo "Skipped installer-managed files: greeter via just greeter-sync --install; SSH server via just ssh-server; tuigreet config, Betterbird and the Firefox autoconfig via install.sh"

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

# Apply main to this machine after it changed (applies what is checked out, never pulls: after a merge on GitHub run .claude/skills/ship-batch/ship-batch.sh with no PR numbers, which pulls then applies, or git pull then this; also rerun it to recover from a failed step): restow, reload units, rebuild voxcmd, migrate, reload Hyprland, sync the greeter, restart the bar, for what changed since the last successful run. Waits for a running ship-batch; skips the bar restart and exits non-zero while the screen is locked, so rerun it once unlocked
post-merge:
    bash .claude/skills/ship-batch/post-merge.sh

# Time how long voxcmd takes to route the benchmark phrases in the sandbox (--runs N, --live, --all); see home/voxcmd/tests/bench.sh
voxcmd-bench *ARGS:
    home/voxcmd/tests/bench.sh {{ARGS}}

# Build the Rust voxcmd from this checkout and link it as ~/.local/bin/voxcmd (and the voxcmd-rs alias, kept one release)
voxcmd-build:
    #!/usr/bin/env bash
    set -euo pipefail
    # The binary bakes in the checkout it was built from (its share dir and auto-stop), which a worktree may outlive.
    [ "$(git rev-parse --git-dir)" = "$(git rev-parse --git-common-dir)" ] || { echo "voxcmd-build: run it in the main checkout, not a worktree" >&2; exit 1; }
    root="${XDG_DATA_HOME:-$HOME/.local/share}/voxcmd-rs"
    VOXCMD_GIT_HASH="$(git describe --always --dirty --abbrev=9 --exclude='*')" cargo install --path home/voxcmd --locked --root "$root"
    mkdir -p "$HOME/.local/bin"
    ln -sf "$root/bin/voxcmd" "$HOME/.local/bin/voxcmd-rs"
    ln -sf "$root/bin/voxcmd" "$HOME/.local/bin/voxcmd"
    "$HOME/.local/bin/voxcmd" --version

# The Rust crate's tests, then the voxcmd suites against this checkout's Rust build
voxcmd-test:
    #!/usr/bin/env bash
    set -euo pipefail
    cargo test --locked --manifest-path home/voxcmd/Cargo.toml
    failed=()
    for suite in run-phrases run run-calendar run-wake; do
        "home/voxcmd/tests/$suite.sh" || failed+=("$suite")
    done
    [ "${#failed[@]}" = 0 ] || { echo "suites failed: ${failed[*]}" >&2; exit 1; }

# Sample the running wake word listener's memory and CPU for N minutes; run it on an idle machine
voxcmd-wake-sample minutes="60":
    home/voxcmd/tests/wake-sample.sh {{minutes}}

# Let the greetd login unlock the GNOME keyring (needs sudo); greeter-sync --install and the installer also run it
greeter-keyring:
    #!/usr/bin/env bash
    set -euo pipefail
    export DOTFILES_DIR="$PWD"
    source lib/install/load.sh
    enable_greetd_keyring_unlock

# Remove the retired voxcmd Firefox extension: its host manifest, installed xpi and policy entry (needs sudo)
retire-firefox-extension:
    #!/usr/bin/env bash
    set -euo pipefail
    export DOTFILES_DIR="$PWD"
    source lib/install/load.sh
    retire_voxcmd_firefox_extension

# Tune pacman.conf and makepkg, enable the paccache timer (asks first; needs sudo)
pacman-tweaks:
    #!/usr/bin/env bash
    set -euo pipefail
    export DOTFILES_DIR="$PWD"
    source lib/install/load.sh
    setup_pacman_tweaks

# Snapshot / with snapper and snap-pac on btrfs, with btrfs quotas off (asks first; needs sudo)
snapper:
    #!/usr/bin/env bash
    set -euo pipefail
    export DOTFILES_DIR="$PWD"
    source lib/install/load.sh
    setup_snapper

# Opt in to an SSH server reachable only over Tailscale, key login only (needs sudo)
ssh-server:
    #!/usr/bin/env bash
    set -euo pipefail
    export DOTFILES_DIR="$PWD"
    source lib/install/load.sh
    setup_tailnet_ssh

# Opt in to Syncthing for each repo's .plans and .logs, listening on Tailscale only
syncthing:
    #!/usr/bin/env bash
    set -euo pipefail
    export DOTFILES_DIR="$PWD"
    source lib/install/load.sh
    setup_syncthing

# Add the other machine to Syncthing by device ID and Tailscale address (discovery is off)
syncthing-peer id ip:
    #!/usr/bin/env bash
    set -euo pipefail
    export DOTFILES_DIR="$PWD"
    source lib/install/load.sh
    syncthing_add_peer "{{id}}" "{{ip}}"

# Add the -plans and -logs Syncthing folders (5 simple versions each) for every repo that plans finds
syncthing-folders:
    #!/usr/bin/env bash
    set -euo pipefail
    export DOTFILES_DIR="$PWD"
    source lib/install/load.sh
    syncthing_add_folders

# Copy the laptop's bar state, theme, FF7 lock audio and fonts to an agent host, once (never weather.local.json)
agent-host-seed host:
    lib/install/agent-host-seed "{{host}}"

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

# Pull repos/ checkouts cloned for this machine; linked dev checkouts are skipped. Relinks keeptabs so new commands land in ~/.local/bin
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
    export DOTFILES_DIR="$PWD"
    source lib/install/load.sh
    link_keeptabs

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

# Build the stowed DesertFox TOML config (~/.config/desertfox) into Firefox's managed storage file; DesertFox is found at $DESERTFOX_DIR, default repos/desertfox (set up by `just repos`), and needs `just build` run there first; warns when the checkout is behind its upstream or dist/ is older than its last commit
desertfox-config:
    #!/usr/bin/env bash
    set -euo pipefail
    desertfox="${DESERTFOX_DIR:-{{ justfile_directory() }}/repos/desertfox}"
    [[ -f $desertfox/tools/build-config/cli.ts ]] || { echo "desertfox-config: no DesertFox checkout at $desertfox (set DESERTFOX_DIR)" >&2; exit 1; }
    bash "{{ justfile_directory() }}/lib/install/desertfox-freshness" "$desertfox"
    [[ -f $desertfox/dist/commands.json ]] || { echo "desertfox-config: run 'just build' in $desertfox first" >&2; exit 1; }
    config_dir="$HOME/.config/desertfox"
    [[ -d $config_dir ]] || { echo "desertfox-config: no config at $config_dir (run 'just stow desertfox')" >&2; exit 1; }
    cd "$desertfox"
    node tools/build-config/cli.ts "$config_dir" --live || { echo "desertfox-config: build-config failed. If it says Unknown option '--live', update the DesertFox checkout at $desertfox and run 'just build' there" >&2; exit 1; }

# Install or update the DesertFox native hosts and the desertfox CLI from the latest release (needs network; the Firefox permission click on :native.install stays manual)
desertfox-host:
    bash "{{ justfile_directory() }}/lib/install/desertfox-host"

# Install or update the ArtCraft apps in packages/artcraft.ini from their signed GitHub releases (--check only lists what is behind)
artcraft-update *args:
    bash "{{ justfile_directory() }}/lib/install/artcraft-update" {{ args }}

# Regenerate the generated sections of the docs (the keybind table in docs/keybinds.md, the IPC table in the Quickshell README)
docs-gen:
    python3 -B lib/docs/gen-keybinds --write
    python3 -B lib/docs/gen-ipc --write

# Point git at lib/git-hooks, whose pre-commit runs docs-gen and stages the tables. Keeps a core.hooksPath set elsewhere
git-hooks:
    #!/usr/bin/env bash
    export DOTFILES_DIR="$PWD"
    source lib/install/load.sh
    setup_git_hooks

# Redump the Hyprland bind fixtures from the current keymaps, keeping each file's header. Run it only for a key you meant to change, then read the diff
hypr-fixtures:
    #!/usr/bin/env bash
    set -euo pipefail
    tests="{{ justfile_directory() }}/home/hypr/tests"
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
    # The tests run from a temp dir with SHELL=/bin/zsh, because the menus name the user's shell in their commands.
    export SHELL=/bin/zsh
    for name in global launch stateful submap_rows; do
      fixture="$tests/fixtures/act_${name}_binds.tsv"
      grep '^#' "$fixture" >"$work/$name.tsv" || true
      (cd "$work" && lua "$tests/act_$name.lua" --dump) >>"$work/$name.tsv"
      mv "$work/$name.tsv" "$fixture"
    done
    git -C "{{ justfile_directory() }}" diff --stat -- "$tests/fixtures"
