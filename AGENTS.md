# AGENTS.md

Guidance for coding agents working in this repository. `CLAUDE.md` is a pointer to this file; keep the content here.

## Overview

Personal Arch Linux dotfiles deployed with GNU Stow. Two deployment targets, each independent, plus extras that are never deployed:

- `home/<package>/` — Stow packages symlinked into `~`. Directory layout under a package mirrors `$HOME` exactly (`home/kitty/.config/kitty/` becomes `~/.config/kitty/`).
- `system/` — files rsynced into `/` (`/etc`, `/opt`, `/usr/local/bin`). Not stowed; copied.
- `extras/` — configs imported by hand into other apps (browser extensions). Never stowed or copied; keep anything Stow-shaped in `home/`.

`.stowrc` pins `--dir=home --target=~`, so a bare `stow <package>` from the repo root works, except for the packages in `NO_FOLD_PACKAGES` (`lib/install/stow.sh`: `systemd`, `calendar`). systemd ignores symlinked drop-in and `.wants` directories, so those packages are stowed with `--no-folding` by `do_stow` and the `just` stow recipes; use `just stow`/`restow`, not a bare `stow`, for them. Any new package shipping `~/.config/systemd/user` units or drop-ins goes in that list. `just migrate-systemd [--dry-run]` (`lib/install/migrate.sh`, idempotent) repairs a machine stowed before this. [Why](specs/decisions.md#stow-systemd-and-calendar-unfolded).

## Commands

```bash
just                  # list recipes
just check            # full validation (run before committing)
lib/check.sh --changed origin/main   # only the steps the changed files can affect, skipping those already passed for the same files
lib/check.sh --only voxcmd-click,voxcmd-rust   # just those steps; their passes count for the final --changed run
just lint             # shellcheck install.sh uninstall.sh, lib/check.sh, lib/{common,install,check}/**/*.sh, demo/*.sh and the Quickshell audio importers
just shaders          # rebuild every Quickshell .frag.qsb from its .frag (qsb); the shaders check step fails on a stale one
just stow <pkg>       # symlink one package into ~
just restow <pkg>     # fix stale/broken links
just unstow <pkg>
just stow-core        # packages under [CORE] in packages/stow.ini
just stow-optional    # packages under [OPTIONAL]
just system-diff      # dry-run rsync of system/ into / (no sudo); skips installer-managed files
just system-apply     # apply system/ into / (sudo); skips installer-managed files (greeter via `just greeter-sync --install`, SSH server via `just ssh-server`, tuigreet config and Betterbird via `install.sh`)
just sync-root-yazi   # regenerate root's Yazi keymap
just repos [--dev]    # set up repos/ without a full install
just update-repos     # pull non-linked clones in repos/
./install.sh -m       # minimal install, skips AUR/rust/system files/services
./install.sh --server # headless install, no desktop packages/configs/services
```

`just check` runs everything; `lib/check/README.md` lists the steps and how the options, the heavy-step slots and the pass records work (keep step docs there, not in `lib/check.sh`: an edit to the shim reruns every step). `lib/check.sh` is a shim for `lib/check/runner.py` (stdlib Python 3.11+, always run with `-B`). A new step, or a path that should reach one, goes in the tables of `lib/check/scopes.py`; `lib/check/keys.py` builds the pass-record keys from each step's definition and the files it reads; `scopes.py` is exempt from other steps' keys, so a new `Step` field that can change a pass must be added to `keys.DEFINITION_FIELDS` (a guard test fails otherwise). Branches cut before the port share no passes ([why](specs/decisions.md#key-each-check-step-on-its-own-definition)).

A spec is `specs/core/<id>.md`, copied from `specs/core/TEMPLATE.md`; its front matter and any `.plans/` file's (the generic fields of the orchestrator skills plus `specs`, the list of spec ids it touches) are validated by the `specs` step against `specs/schema/` (`check-jsonschema`, from `packages/pipx.ini`; the step fails without it). Each requirement id (`- **BAR-03** ...`) is tagged in a test with `req: BAR-03` (a comment or a `vectors.tsv` note; several ids comma-separated) or marked `[gap: untested]` or `[gap: unmet]`; `lib/check/steps/specs.py --write` regenerates `specs/gaps.md`. Tooling tests and voxcmd goldens stay untagged.

Formatting scope is deliberately narrow — whitespace and stylua checks only cover `install.sh`, `uninstall.sh`, `justfile`, `lib/`, `packages/`, `home/hypr/`, and shfmt covers the Quickshell audio importers (`scripts/*-audio`, `scripts/lib/`) and the agent tooling's tracked shell scripts under `.claude/` and `home/claude/.claude/` (skills, hooks, `status.d`; written here, not vendored). Everything else under `home/` is vendored or hand-maintained upstream config; do not reformat it.

## Installer architecture

`install.sh` is a thin orchestrator: parse flags, then call functions sourced from `lib/`. `lib/common/` holds the helpers `uninstall.sh` and the justfile share: `packages.sh` (manifest reading + pacman/pipx/luarocks), `distro.sh`, `output.sh` (`info`/`warn`/`success`/`die`) and `greeter-files.sh` (the Quickshell files the greeter stages). `lib/install/` holds the install steps, each file one concern — `arch.sh` (paru/AUR), `rust.sh`, `fonts.sh`, `stow.sh` (stowing only: `stow_packages`, `NO_FOLD_PACKAGES`, generated defaults), `dev-tools.sh` (dev runtimes, tmuxifier, git identity, Neovim config and plugins), `system.sh` (system files, default shell, keyd, power profiles, root symlinks), `hardware.sh` (Nvidia, xone, Steam), `snapper.sh` (snapper snapshots of a btrfs `/`, btrfs quotas off), `greeter.sh` (greetd, the Quickshell greeter, the greetd keyring unlock, the greeter's `monitors.lua` generated from the session's machine profile by `greeter-monitors.lua`; define-only at source time), `voice.sh` (voxtype, voxcmd's Firefox host and extension policy), `calendar.sh` (the calendar sync timer and its `calendar-sync setup` offer when the optional `calendar` package is stowed), `repos.sh` (external repos in `repos/`), `migrate.sh` (one-time layout migrations), `tailnet-ssh.sh`; their tests are in `lib/install/tests/`.

`lib/install/load.sh` loads `common/output.sh`, `distro.sh`, `packages.sh` and every `install/*.sh`; callers (`install.sh`, `uninstall.sh`, the justfile recipes) set `DOTFILES_DIR` and source only it, so a file under `install/` must only define at source time (`lib/install/tests/load.sh` enforces silence). Distro detection is `require_arch` (sets `$DISTRO`, prints `Detected:`, dies off Arch), called by `install.sh` and `uninstall.sh` only. The check steps and the Quickshell status source `common/greeter-files.sh` or `install/greeter.sh` directly instead.

New install behavior belongs in the matching lib function, not inline in `install.sh`.

## Package manifests

`packages/*.ini` are the single source of truth for what gets installed. Plain lines are entries; `#`, blanks, and `[SECTION]` headers are skipped. `read_pkgs` reads a whole file, `read_ini_section <file> <SECTION>` reads one section.

- `arch.ini` / `arch-aur.ini` / `pipx.ini` / `luarocks.ini` / `devtools.ini` — package names.
- `nvidia.ini` — Nvidia driver packages, read by `install_nvidia` only after its prompt (`[USERSPACE]` plus `[DKMS]` or `[MODULE]`).
- `ssh-server.ini` — packages for the Tailscale-only SSH server, read by `setup_tailnet_ssh` only after its prompt.
- `snapper.ini` — snapper and snap-pac, read by `setup_snapper` only after its prompt and only on a btrfs `/`.
- `stow.ini` — dotfile package names (`[CORE]` auto-stowed, `[OPTIONAL]` fzf-selected, `[SERVER]` used instead of `[CORE]` under `--server`).
- `repos.ini` — git repositories to clone.

`lib/check/steps/packages.sh` fails on a name appearing in two manifests, excluding `stow.ini` and `repos.ini` (those namespace directories and repos, not packages). It also fails when a `stow.ini` entry has no `home/` dir, or a `home/` dir is in neither `stow.ini` nor its `unstowed` list. Adding a package means editing the manifest, not the installer.

An `[MANUAL]` section's comment lines in `arch.ini` are printed as post-install notes.

## Git config

`home/git/.config/git/config` is tracked and ends up at `~/.config/git/config`. It includes `identity`, a gitignored file holding only `[user]`; `setup_git_identity` writes it on install when absent and never overwrites one. Keep name and email out of the tracked config, the repo is public.

## Merging

Every PR merge goes through `.claude/skills/ship-batch/ship-batch.sh <n>...` (PRs in merge order), whether the owner said "merge N" or a standing approval covers it. `merge-prs.sh` is for `--check` only; a hook blocks it and the `gh` merge command otherwise. After a PR was merged on GitHub by hand, run `ship-batch.sh` with no arguments for the post-merge steps.

## Hyprland config

`home/hypr/.config/hypr/` is Lua, not `hyprland.conf`. `hyprland.lua` is the entrypoint; it merges machine config (`config/machines/`) and loads the `hyprvim` plugin (Vim-modal window management with a which-key overlay). Subsystems live in `config/`, `keymaps/`, `extensions/`, `lib/`, `scripts/`, `theme/`. This tree is stylua-checked.

Hyprland runs this Lua config, so drive it with the Lua API: `hyprctl keyword` fails, and `hyprctl dispatch` takes an `hl.dsp.*` expression (`hyprctl dispatch "hl.dsp.exec_cmd('qs -n')"`), not a dispatcher name like `exec` or `movecursor`. Use `hyprctl eval '...'` for anything else, including `hl.config({ ... })` in place of `keyword`.

After a re-login `HYPRLAND_INSTANCE_SIGNATURE` in long-lived shells is stale: the live instance is the newest socket under `$XDG_RUNTIME_DIR/hypr` that answers `hyprctl monitors`. Kill `qs` by PID rather than relying on `hyprctl`.

The 14 tool actions (zoom, screenshot, voice, passwords, overview, tmux overview) are defined with `Act.define` in `lib/actions/defs/tools.lua`, and the clipboard, clipboard-delete, directory and emoji pickers plus the HyprVim terminal and jump-to-mark keys in `lib/actions/defs/pickers.lua` (function actions, so a picker keeps its rofi fallback); `keymaps/global/tools.lua` loads both. The keyless IPC actions (`lock.open`, `style.*`, `zoom.*`, `overview.*`, `settings.*`, `picker.*` and more, one file per bar area) sit in the other files of `lib/actions/defs/`, and `keymaps/global/keyless.lua` loads them: a defs file no keymap requires is never in the live session. `Act.define` registers the action and binds its keys (label, extra keys and `opts` included), `Act.bind` adds a key with args (its `desc` gives that key its own which-key label, or `false` none; a define's `opts.desc` is ignored), and `Act.run`/`Act.run_cli` perform one by id (`lib/act.lua`). `Ipc` and `Cmd` take split argv. Lua is the only source: no list of actions is committed. `hypr-act list` (`home/hypr/.local/bin/hypr-act`) prints the live session's list as JSON, and with no Hyprland answering it prints nothing and exits 3 (4 when Hyprland runs but the list cannot be read); `hypr-act <id> [args...]` runs any action through `hyprctl eval` and `Act.run_cli`, silent on success, exit 5 when the action fails (unknown id, bad argument, Lua error); the `registry` step loads `lib/actions/defs/*.lua` under stubs (`home/hypr/tests/act_refs.lua`, which needs a stub line for any new `require`) and checks the ids, IPC functions and `~/` scripts they name ([why](specs/decisions.md#lua-defines-actions-hyprland-is-the-registry)). A new bind or typed IPC function needs an action, or a reasoned line in `lib/check/registry.allow`; the `registry` step fails on one without, and on a stale line ([why](specs/decisions.md#binds-and-ipc-functions-need-an-action-or-a-reasoned-allow-line)).

User overrides live in two gitignored places, and tracked files must stay generic: `Config` values (hardware, default apps) in `config/machines/<hostname>.lua`, and everything built on the loaded library (binds, rules, launcher sessions) in `custom/`, whose `custom/init.lua` `hyprland.lua` requires last if present. Never auto-load other files in `custom/` from the Hyprland config. The one exception is the wallpaper rotator, a separate process that `custom/init.lua` cannot reach: it reads `custom/wallpaper.lua` and `custom/hyprpaper.conf` itself when present. Register binds through `lib/key/bind.lua` (`Bind.key`, `Bind.submap`), never raw `hl.bind` or `hl.define_submap`, so `Bind.unbind` can remove a key from one submap ([why](specs/decisions.md#unbind-a-key-from-one-submap-only)). `Bind.unbind` and `Bind.submap` are public API for `custom/`; keep their signatures stable.

## Interaction conventions

How the owner expects anything interactive to behave, in Quickshell, voxcmd or a script. Agree a new surface's keys, look and first run with the owner before building it.

- Keyboard first. Every action has a key; the mouse is a shortcut, never the only way.
- vim semantics: `hjkl` move, Shift+`HJKL` the bigger step (month, year), `n`/`N` next and previous match, `gg`/`t` the start or today, `c` create, `o` open, `e` edit, `x` remove, Enter the main action, Esc or `h` back one level, `q` close.
- Bar markers stay small (a dot, a count, a few characters); the detail goes in the tooltip or the popup.
- A link opens in the default browser (`xdg-open`, Settings > Default apps) and the browser window is focused, not left behind.
- Public features work for anyone: never assume the owner's tools (rbw, Firefox, a particular terminal). Offer a guided setup for the common case and a config key for the rest.

## Quickshell key conventions

Keep keys consistent across surfaces; new popups, pickers and skins follow these:

- Popups (`features/popups/frames/Popup.qml`; keys in `features/popups/frames/PopupKeys.qml`): Tab/Shift+Tab step the top tabs, `[`/`]` step the bottom views; a popup with only one level answers both. Number keys pick a tab. Clock: Tab and `[`/`]` cycle timezones.
- Settings panes: `h` (and Esc, Tab) goes back to the sidebar and `l` or Enter goes in, like a file manager; a pane with nested views (Sessions) steps `h` and Esc up one view at a time and reaches the sidebar from its top view; a row's value steps with `l`/Space forward and Shift+`H`/`L` either way, so a section must leave plain `h` unused. `{`/`}` jump between a section's headings (`RowsSection`). `Ctrl+D`/`Ctrl+U` move half a page in the section list, a pane and an open list (`SettingsPopup.half_page_pane`), except that while typing in an open list's filter (INSERT) `Ctrl+U` clears it and only `Ctrl+D` pages; in NORMAL both page.
- Overviews (workspace and share picker): `s` selects a whole screen, `w` sends the selected workspace to a monitor and `W` swaps it with another workspace (both confirm with Enter), Tab/Shift+Tab switch regular and special workspaces, `[`/`]` cycle windows, `f` toggles the view; in the share picker `r` opens the region selector and Esc there comes back.
- A popup action that opens a window (terminal, editor, file manager) launches it through `Popups.after_close(fn)`, never `Popups.close()` followed by a launch: a window that maps while the popup holds the keyboard ends up unfocused ([why](specs/decisions.md#launch-windows-from-popups-after-the-popup-closes)).
- Lock and greeter input is a vim model owned by the shared router (`Lock.key`, `Greeter.key`): NORMAL while nothing is typed, where `h/j/k/l` navigate skin menus and `h`/`l` do nothing on vertical lists; `i` or any other printable key enters INSERT (`-- INSERT --` shows bottom-left); Esc on an empty buffer returns to NORMAL. The skin contract is in `home/quickshell/.config/quickshell/features/lock/README.md`.
- `x` removes or forgets the selected thing (closes a window in the overview, forgets a Bluetooth device or network). Forgetting and deleting saved data first ask a `y`/`n` prompt naming what goes; `q` still closes from the prompt.
- Picker lists step rows with Tab/Shift+Tab, except a provider whose items expand into lists of their own (`PickerProvider.expands`, e.g. Voice Help): there Tab expands the selected item, as Tab completes in HyprVim's prompt, and Backspace on an empty search goes back.
- Full-screen interactive modes (pickers, zoom) follow `RegionSelector`: Quickshell owns keyboard and pointer and has a `?` help box; never a Hyprland submap. Modes where the keyboard moves the pointer (pickers, region select, zoom) load the skin cursor from `features/screen_select/cursors`; others (e.g. the bar editor) keep the system cursor.
- Never hand-edit the `BEGIN generated` block in `Style.qml`: edit `theme/StyleSchema.js` and run `scripts/gen-style-exports` (in the Quickshell dir). Adding a style or token: `theme/README.md`.
- Times use `TimeFormat` and `ClockSettings` (Settings > Date & time); state paths use `core/Paths.qml` and `lib/state.lua` instead of recomputing XDG dirs; a settings file is a `core/JsonStore.qml` child of its store singleton, not a hand-built timer plus `mkdir/printf/mv`.

## Quickshell structure

`QS` is `home/quickshell/.config/quickshell`; `QS/README.md` indexes the folders and per-feature docs. Each rule points to where it is enforced or explained. Reviewers check Quickshell diffs against this section.

- Layers: a file imports its own layer or a lower one, in the order of `LAYERS` in `lib/check/steps/qml_layers.py` (`qml-layers`; the ranks change there, not here). `core/` imports nothing outside `core/`. A kept upward edge goes in `lib/check/qml-layers.allow`; delete the line in the PR that removes the edge.
- Imports: folders as `import qs.<path>`, JS relative (`import "Tints.js" as Tints`). `qml-layers` also fails a relative import from one feature, or one style, into a sibling; go through a singleton (the kept edges are `SIBLING_ALLOW` in `lib/check/steps/qml_layers.py`). `import qs.features.<y>` across features is unchecked.
- String-built paths and table-driven loads: `qml-paths` (`lib/check/steps/qml_paths.py`) lists the rules and the `// qs-path:` markers.
- Singleton names: `qml-singleton-names`; `QS/README.md` "Naming singletons".
- Where a new file goes (not machine-checked): shared by several features and style-neutral, `ui/`; used by one feature, that feature's folder; one style's drawing, that feature if one uses it, else `styles/<name>/`. Exception: a single-style widget with three or more consumers (`MateriaOrb`, `VisorGlass`, `HandCursor`) lives in `ui/`.
- Greeter-staged files: any file the greeter loads is listed in `lib/common/greeter-files.sh`, edited in the PR that adds, moves or deletes it; ship-batch re-syncs the greeter from that list. A lock skin imports only files the greeter stages (not another skin, not `qs.services`); the contract is `home/quickshell/.config/quickshell/features/lock/README.md`, "A lock skin".
- Tests: a check step's tests are `lib/check/tests/test_<step>.py`; a runtime QML test is `home/quickshell/tests/<name>/run.sh` with its own Step and `PATH_SCOPES` rule in `lib/check/scopes.py`. Run them through `lib/check.sh --only <step>` so the pass counts.
- Docs: `readme-links` (`lib/check/steps/readme_links.py`) fails a dead link, anchor or backticked path in a Quickshell README. It does not read this file.

## voxcmd

Test voxcmd actions through `home/voxcmd/tests/sandbox.sh`, never against the live desktop; add a phrase to `home/voxcmd/tests/phrases.tsv` for every new or fixed phrasing. Run a whole suite, or the crate's `cargo test`/`clippy`, as its check step (`lib/check.sh --only voxcmd-phrases`, `voxcmd-click`, `voxcmd-calendar`, `voxcmd-wake`, `voxcmd-firefox`, `voxcmd-rust`; the output-sink ducker's suite is `voxtype-duck`), not by hand: a hand run records no pass, so the final `--changed` run repeats it behind the check lock (`.claude/hooks/warn-direct-voxcmd-suite.sh` warns). Iterating on one section with `VOXCMD_ONLY_SECTIONS=` by hand is fine; a check run with it set records no voxcmd pass. When the owner should try a voxcmd branch by voice before merging, put it live with the `owner-test-bar` skill (`up <name> <branch>`, then `restore`), which swaps voxcmd's links to the branch and back; the installed voxcmd is the build from the main checkout.

Regenerate the voxcmd goldens (`home/voxcmd/tests/fixtures/*-goldens.tsv`) only with the owner's sign-off. The Rust crate is `voxcmd` (`just voxcmd-build` links it as `~/.local/bin/voxcmd`; ship-batch rebuilds it after a crate merge). The goldens are frozen, their generators gone. Integrations are TOML in `integrations/`. The port's status and phase table are in [specs/voxcmd-port.md](specs/voxcmd-port.md).

Firefox tabs are listed and switched by the companion extension in `extras/voxcmd-firefox/` when it is loaded: a native-messaging host (`home/voxcmd/.local/share/voxcmd/firefox-host`, stdlib Python) bridges it to `$XDG_RUNTIME_DIR/voxcmd/firefox.sock`, which `firefox-tab` asks first, falling back to the session store and the address bar. One-time setup: `just firefox-host` (also run by the installer) registers the host, whose manifest needs an absolute path and so is generated, not stowed; `just firefox-extension` (also run by the installer, via `lib/install/voice.sh`) installs the signed `extras/voxcmd-firefox.xpi` through a Firefox policy; sign with `just sign-firefox-extension` (its README covers updates and removal). Tests: `lib/install/tests/firefox-policy.sh` (the `firefox-policy` check step; overridable paths, no sudo), `home/voxcmd/tests/run-firefox-extension.sh` (the `voxcmd-firefox` check step) and run.sh's "firefox live" section.

## Betterbird / tbkeys

`home/thunderbird/.config/tbkeys/*.js` are loaded in a fixed dependency order by `loader.js` beside them, the only file `system/opt/betterbird/betterbird.cfg` loads; keep the module list there, since the installed `.cfg` is not refreshed by stowing — later modules may call earlier ones, never the reverse. `core.js` runs the previous load's teardown hooks and recreates `window.tk` from scratch. See `home/thunderbird/README.md` for the full module responsibility table; put new behavior in the module that owns that responsibility rather than reimplementing primitives.

`keys.json` and `quicktext.json` are tracked copies, not read from disk — after editing, paste into the add-on's options page. Restart Betterbird after editing any module.

## Yazi packages

Plugins are managed by `ya pkg`, with `home/yazi/.config/yazi/package.toml` as the manifest. Package-managed plugin directories are gitignored; only the local `folder-rules.yazi` plugin is tracked. Never hand-edit package metadata or copy upstream plugin files — run `ya pkg add/delete/upgrade` and commit the resulting `package.toml`.

## External repos

This repo has no submodules. `lib/install/repos.sh` sets up every repo in `repos.ini` (`owner/name` entries) plus the Neovim config under the gitignored `repos/` directory. By default each is cloned there over HTTPS. `$GITHUB_DIR` (default `~/Development`) and `$GITHUB_ORG` (default `uhs-robert`) can be overridden by the environment or an ignored `install.local` in the repo root (environment wins); `lib/common/distro.sh` reads it. With `./install.sh --dev`, or when `$GITHUB_DIR/<section>/<name>` already exists, the checkout lives under `$GITHUB_DIR` and `repos/<name>` is a symlink to it, so there is only ever one copy. `just update-repos` pulls the non-linked clones.

`lib/check/steps/symlinks.sh` fails on a tracked symlink that dangles or points outside the repo; links into a `repos/` clone that is not set up yet are skipped.

Tracked files must reach external repos only through `repos/`: theme files are relative symlinks into `repos/oasis.nvim/extras`, and `hyprvim` and `deserted-everything-css` are symlinks into `repos/`. Runtime configs that cannot find the dotfiles checkout (shell rc files, Hyprland env) use `~/.local/share/dotfiles/repos`, which the installer links to `repos/`. Never hardcode `~/Development`.

`install_nvim_config` links `~/.config/nvim` to `repos/<name>` for `$NVIM_CONFIG_REPO` (default `uhs-robert/neovim`, also accepts a git URL), leaving any existing `~/.config/nvim` untouched.

## Docs

`docs/` is for users: written for someone who has not read the code, leading with what to do. `specs/` is for agents and developers: the roadmap, the specs, durable plans and the decisions log. A feature's README stays beside its code and links to its spec. Neither repeats a rule from this file; link to it.

`.plans/<topic>/<topic>.md` holds the tracker for work in progress (batch order, open points), with its plan drafts beside it; `.logs/<topic>/` holds its evidence (check output, review notes, PR bodies). Whoever owns the topic deletes both once it is merged or dropped, after moving anything durable (a decision, a status) into `specs/` in the last PR. They exist in the main checkout only (both are gitignored, so worktrees do not see them); briefs give their absolute paths. An agent without a path finds the main checkout as the parent of `git rev-parse --path-format=absolute --git-common-dir`.

## Global agent files

Everything tracked under `home/claude/.claude/` (skills, agents, commands, hooks, `status.d`) is symlinked to `~/.claude/` and loaded in every project, so each line must hold in an unrelated repository (a Python web app, a Rust CLI). Project-specific guidance goes in this file or in `.claude/skills/`. Reviewers of any diff touching `home/claude/.claude/` flag every line that fails this test, whatever its subject.

## Gitignore

`.gitignore` ignores credentials, AI assistant state and generated config by default ([why](specs/decisions.md#gitignore-ignores-by-default)). `home/claude/**`, `home/gemini/**`, `home/codex/**` are ignored except for explicitly negated subpaths (agents, commands, skills, settings). Adding a new tracked file under those trees requires a matching `!` negation.

`CLAUDE.md`, `GEMINI.md`, and `AGENTS.md` are ignored everywhere except at the repository root — `!/CLAUDE.md` and `!/AGENTS.md` keep the top-level agent instructions tracked. A nested `AGENTS.md` under `home/` stays ignored.
