# oasis-djinn

One list of what the desktop can do, independent of the tool that does it, and `oasis-djinn` to run any of it.

- `.config/oasis-djinn/actions.json`: each action's `id` (`area.verb`), `label`, `intent`, positional `params` (`int`, `float`, `string`, `bool`, `enum` with `values`; a `default` makes one optional), its default `key` and `extra_keys`. A key is `{key, leader, universal}`: `leader` puts it behind the leader key, `universal` keeps it live inside submaps. Schema: `specs/schema/actions.yaml`.
- `.config/oasis-djinn/bindings/quickshell.json`: how the bar performs each id, either `ipc` (`target`, `function`, `args`) or `command` (`argv`, for what has no IPC function). A word may hold `{param}`; `~/` starts a home path. Schema: `specs/schema/bindings.yaml`.
- `src/`, `Cargo.toml`: the Rust crate. `src/lib.rs` (package `oasis-djinn`, lib `oasis_djinn`) loads the manifest and bindings, checks params and plans the command; `src/main.rs` is the `oasis-djinn` binary over it. voxcmd can depend on the library by path (`oasis-djinn = { path = "../oasis-djinn" }`) when it gains `action = "<id>"`. It reads `serde_json` only, no async runtime.
- `oasis-djinn <id> [param...]`: exit 0 done, 1 the performer failed or would not start, 2 an unknown id, bad param or unreadable manifest (nothing runs). It needs the logged-in session: it calls the bar through `~/.config/hypr/scripts/qs-ipc`. `OASIS_DJINN_CONFIG_DIR` points it at another manifest folder.

`oasis-djinn` is built, not stowed: the installer runs `build_djinn` (`lib/install/djinn.sh`) after stowing, which `cargo install`s the crate under `~/.local/share/oasis-djinn-rs` and links `~/.local/bin/oasis-djinn`; `just djinn-build` does the same by hand. A machine without cargo (`--no-cargo`) gets no `oasis-djinn` until Rust is installed. The Hyprland binds no longer use it: they call `Act.run` in-process.

Order on a machine that already runs the desktop: build and link the runner, then stow the manifest. `./install.sh` does the first two in that order (the `oasis-djinn` entry in `packages/stow.ini` `[CORE]`, then `build_djinn`); by hand: `just stow oasis-djinn && just djinn-build`, then reload.

Add an action: an entry in `actions.json`, an entry with the same id in `bindings/quickshell.json`, then `lib/check.sh --only registry,djinn-rust`. The step fails a duplicate id, a missing or stray binding, and an IPC function or script that does not exist. The Hyprland keys come from `Act.define` in `home/hypr/.config/hypr/lib/actions/defs/tools.lua`, not from this manifest, so a new action needs a define there too until the manifest is deleted. The clipboard, directory and emoji pickers stay `Menu.*` binds for now: they fall back to rofi when the bar has no provider, which an IPC binding cannot.

Try it: `oasis-djinn zoom.toggle`.
