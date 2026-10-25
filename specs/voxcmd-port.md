# voxcmd port: bash to Rust

Status of the rewrite of voxcmd (`home/voxcmd/`) as one Rust binary. It carries no spec front matter and the `specs` check does not scan it. The rules for working on voxcmd are in [AGENTS.md](../AGENTS.md#voxcmd); this file holds only the port status.

## What runs today

The bash `voxcmd` stays installed and live until item 3.2 swaps it. The Rust port is the crate in `home/voxcmd/` (`Cargo.toml`, `src/`; stow ignores it). `just voxcmd-build` installs it as `voxcmd-rs`.

Until 3.1 converts the bash integrations to TOML, the Rust binary reads them through the bash voxcmd's hidden `_legacy-dump` (`src/config/legacy.rs`, cached under `~/.cache/voxcmd`; `VOXCMD_LEGACY_BIN` names the script). An `integrations/<stem>.toml` wins over `integrations.d/<stem>.sh`.

The click actions are Rust built-ins. A TOML action with `provider = "screen_text"` (and `run = "click_at <button>"`) reads the focused window. The bridge hands the shipped `integrations.d/click.sh` to them, with `picker = "hints"` for the numbered boxes. The bridge recognises that file by its hooks, action commands and `pick_command` in the dump, so an edit to those keeps the copy on bash. Edits inside function bodies, or to variables the dump lacks (`filler_words`, `click_target_max_age`, `click_ocr`), are not seen.

The hidden `voxcmd internal click-match` (stdin, `CLICK_TARGET`) is the click matcher, which run.sh's matcher sections call under `VOXCMD_BIN=rs`. `internal click-ocr` and `internal click-at` (the click itself, which prints the reason and exits 1 on failure) are likewise reachable. All of these go with the bash matcher in 3.2.

## Running the Rust binary

- `VOXCMD_BIN=rs` makes `home/voxcmd/tests/sandbox.sh` build this checkout and put the Rust binary first on PATH. The default is `bash`.
- `just voxcmd-test` runs `cargo test` and then the suites that way.
- `tests/run-phrases.sh` passes under `rs`. `VOXCMD_ROUTE_DIFF=1` explains every phrase with both binaries and reports each difference.
- The other suites fail under `rs` until their items (2.3 and later) land.
- `cargo test` compares the ported text parsers, the verb matcher and the click matcher with goldens made from the bash and awk by `tests/fixtures/gen-speech-goldens.sh`, `gen-match-goldens.sh` and `gen-click-goldens.sh`. Regenerate them only with the owner's sign-off.

## Phases

Status values: `todo`, `planning`, `approved`, `in progress`, `in review`, `owner test`, `merged`, `dropped`.

| #   | Item | Status | Notes |
| --- | ---- | ------ | ----- |
| 3.1 | Convert integrations to TOML | in progress | Batches of about five, smallest first, suites green against `voxcmd-rs` each time. TOML text placeholders capture lazily (`.+?`) while the legacy dialect stays greedy. Update the `.gitignore` allowlists in `integrations.d/` and the README's Integrations section. |
| 3.2 | Swap the installed binary | todo | `voxcmd` becomes the Rust binary; the bash script, folded helpers and hidden `internal` entry points are deleted; every caller moves to the new CLI. Owner test before merge. |
| 3.3 | Built-in providers | todo | Move hot `candidates()` lookups (windows, workspaces, monitors, devices) into Rust, one provider per PR. |
| 3.4 | README rewrite | todo | `home/voxcmd/.config/voxcmd/README.md` rebuilt around the new format; the schema and `voxcmd integrations examples` as the reference. |
| 3.5 | Simplify after the swap | todo | Until 3.2 the port keeps strict bash parity. After it, one design-gated PR per subsystem: in-process ask with a single IPC answer path from the bar; table-driven reply parsing proven by reply goldens; removal of test-coupled choices; cleanup of the kept awk quirks. Each is planned with the owner first. |
| 4.1 | Port `voxcmd-wake` | todo | The Python wake listener becomes `voxcmd wake listen` as the service entry; the `wake.json` format is unchanged. Memory and CPU must land well under today's; false-accept and miss rates must match on recorded samples before the owner test. |
| 4.2 | Port `voxcmd-autostop` | todo | Python today; shares capture with 4.1. |
