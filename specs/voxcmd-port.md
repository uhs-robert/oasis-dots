# voxcmd port: bash to Rust

Status of the rewrite of voxcmd (`home/voxcmd/`) as one Rust binary. It carries no spec front matter and the `specs` check does not scan it. The rules for working on voxcmd are in [the voxcmd README](../home/voxcmd/.config/voxcmd/README.md#code); this file holds only the port status.

## What runs today

The Rust crate in `home/voxcmd/` (`Cargo.toml`, `src/`; stow ignores it) is `voxcmd`. `just voxcmd-build` (run by the installer and by ship-batch after a merge that touches the crate) builds it from the main checkout into `~/.local/share/voxcmd-rs` and links `~/.local/bin/voxcmd` to it; `voxcmd-rs` is an alias for the same binary, kept one release. The build bakes in its checkout (share dir, auto-stop), so `voxcmd-build` refuses to run in a worktree. The wake listener (`voxcmd-wake`) and auto-stop stay Python until 4.1 and 4.2, and call `~/.local/bin/voxcmd`.

Integrations are the TOML files in `~/.config/voxcmd/integrations/`. The bash voxcmd, its helpers (`voxcmd-pick`, `-confirm`, `-hints`, `-wake-switch`) and the bash `integrations.d/*.sh` are gone; `voxcmd timer ring` replaces `voxcmd-alarm`. A leftover `integrations.d/*.sh` is not read, and `voxcmd integrations check` warns about it. `VOXCMD_STAND_IN_BIN` only names where the tests' stand-ins put the share dir and auto-stop.

The hidden `voxcmd internal click-match`, `click-ocr` and `click-at` are the click matcher, OCR and click that run.sh's matcher sections and the click tests call; they stay as test entry points.

## Running the Rust binary

- `home/voxcmd/tests/sandbox.sh` builds this checkout and puts the Rust binary first on PATH; every suite runs through it.
- `just voxcmd-test` runs `cargo test` and then the suites.
- `cargo test` compares the ported text parsers, the verb matcher and the click matcher with goldens (`tests/fixtures/*-goldens.tsv`) made from the bash and awk before the swap. Their generators are deleted, so the goldens are frozen: the Rust code is the reference, and a change is a hand edit with the owner's sign-off.

## Phases

Status values: `todo`, `planning`, `approved`, `in progress`, `in review`, `owner test`, `merged`, `dropped`.

| #   | Item | Status | Notes |
| --- | ---- | ------ | ----- |
| 3.1 | Convert integrations to TOML | in progress | Batches of about five, smallest first, suites green against `voxcmd-rs` each time. TOML text placeholders capture lazily (`.+?`) while the legacy dialect stays greedy. Update the `.gitignore` allowlists in `integrations.d/` and the README's Integrations section. |
| 3.2 | Swap the installed binary | owner test | `voxcmd` becomes the Rust binary; the bash script, folded helpers and hidden `internal` entry points are deleted; every caller moves to the new CLI. Owner test before merge. |
| 3.3 | Built-in providers | todo | Move hot `candidates()` lookups (windows, workspaces, monitors, devices) into Rust, one provider per PR. |
| 3.4 | README rewrite | todo | `home/voxcmd/.config/voxcmd/README.md` rebuilt around the new format; the schema and `voxcmd integrations examples` as the reference. |
| 3.5 | Simplify after the swap | todo | Until 3.2 the port keeps strict bash parity. After it, one design-gated PR per subsystem: in-process ask with a single IPC answer path from the bar; table-driven reply parsing proven by reply goldens; removal of test-coupled choices; cleanup of the kept awk quirks. Each is planned with the owner first. |
| 4.1 | Port `voxcmd-wake` | todo | The Python wake listener becomes `voxcmd wake listen` as the service entry; the `wake.json` format is unchanged. Memory and CPU must land well under today's; false-accept and miss rates must match on recorded samples before the owner test. |
| 4.2 | Port `voxcmd-autostop` | todo | Python today; shares capture with 4.1. |
