# Roadmap: specs, one command registry, generated docs

A plan only. Counts measured on main at 6a7ed8924 (2026-10-25); re-measure before relying on them. Items are in priority order; 3 and 4 are cheap and can ship first.

| #   | Item                                         | PRs (estimate) | Depends on         |
| --- | -------------------------------------------- | -------------- | ------------------ |
| 0   | Split docs/ (users) from specs/ (developers) | 2              | none               |
| 1   | One command registry                         | 7              | 0                  |
| 2   | Docs generated from code, with a drift check | 2              | 1 (first 3 PRs)    |
| 3   | AGENTS.md rules only; decisions log          | 1              | 0                  |
| 4   | voxcmd port status out of AGENTS.md          | 1              | 0                  |
| 5   | A short spec per new interactive surface     | 1              | 0                  |
| 6   | More executable specs (tables, goldens)      | 1 per area     | none; some on 1    |
| 7   | One bad-input test across every command      | 2              | 1                  |

Suggested ship batches: B1 = 0a, 3, 4, 5. B2 = 0b, 1a, 1b. B3 = 1c, 1d, 2a. B4 = 1e, 1f, 2b, 7a. B5 = 1g (after the voxcmd 3.2 swap), 7b. Item 6 PRs fit any batch.

Out of scope: parity scorecards, a large docs/ tree, a shared cross-repo rules or CI repo.

## 0. docs/ vs specs/

**Today.** `docs/` holds `keybinds.md` (204 lines) and `sounds.md` (128 lines), both user guides. Feature docs live beside the code (`QS/README.md`, 8 `features/*/README.md`, the Hyprland and voxcmd READMEs). Plans live in the git-excluded `.planning/` and never reach review.

**Scope.**
- AGENTS.md rule, under a new "Docs" section: "`docs/` is for users: how to use and change the setup. `specs/` is for agents and developers: the roadmap, plans, surface specs and the decisions log. A feature's README stays beside its code. Neither folder repeats a rule from this file; link to it."
- Moves: none at first. `docs/` already fits. Items 3, 4 and 5 add `specs/decisions.md`, `specs/voxcmd-port.md` and `specs/surfaces/`.
- readme-links: `lib/check/steps/readme_links.py` lists only `*.md` under the Quickshell tree (`run_checks`, `qs_dir`), so `docs/` and the root README are unchecked today. Recommendation: extend it to `docs/` and `specs/` for links and anchors; check backticked paths in `docs/` and `specs/decisions.md` but not in plans, which name files that do not exist yet (this roadmap does).

**PRs.** 0a: the AGENTS.md rule and this file. 0b: readme-links over `docs/` and `specs/`, with cases in `lib/check/tests/test_readme_links.py`.

**Checks.** `readme-links` is a "tree" step and always runs; `*.md` maps to scope `""` in `PATH_SCOPES`, so no `scopes.py` change is needed. Its line in `lib/check/README.md` ("reads only the Quickshell tree") changes.

**Risks.** Dead links already in `docs/` surface; fix them in 0b.

## 1. One command registry

**Today, measured.**
- Quickshell IPC: 22 files with an `IpcHandler` under `QS` (one handler each, 22 targets), plus `demo/overlay/shell.qml` (`demo`): `audio/SoundIpc`, `bar/CommandStatusIpc`, `clock/CalendarIpc`, `display/BrightnessIpc`, `display/ZoomIpc`, `launcher/HyprvimPromptIpc`, `launcher/PickerIpc`, `lock/LockIpc`, `notifications/NotificationsIpc`, `osd/OsdIpc`, `overview/OverviewIpc`, `overview/TmuxOverviewIpc`, `popups/ConfirmIpc`, `popups/PopupIpc`, `popups/WhichKeyIpc`, `power/PowerIpc`, `screenshot/ScreenshotIpc`, `settings/SettingsIpc`, `style/StyleIpc`, `voice/ClickHintsIpc`, `weather/WeatherIpc` (all under `features/`) and `theme/transitions/TransitionsIpc`. Those files hold 102 `function` declarations. 72 tracked non-Markdown files mention `qs ipc`, `qs-ipc` or `qs_ipc`, most in voxcmd (tests, `integrations.d/`, `src/`) and `home/hypr/.config/hypr/scripts/`.
- The `qml-ipc` step (`lib/check/steps/qml_ipc.py`) already ties callers to handlers: every called target and function must exist, every handler must be called (exceptions in `lib/check/qml-ipc.allow`), and the `QS/README.md` "IPC" table must match.
- Hyprland: the 7 `keymaps/global/*.lua` files bind through `lib/key/bind.lua` (`Bind.key`, `cmd`, `fn`, `keys` rows, the `leader_*` forms; 76 call sites); the 11 submaps under `keymaps/submaps/` use `Submap.define` (`lib/key/submap.lua`) with row tables. The action is a dispatcher, a shell string (often `Scripts.qs_ipc .. " call zoom toggle"`) or a function from `lib/actions/`; the label is the `desc`.
- hyprvim (`repos/hyprvim`, a separate repo) and the Quickshell keybinds picker read those descs back from Hyprland. hyprvim also calls the `hyprvim_prompt` and `hyprvim_whichkey` IPC targets (frozen in `qml-ipc.allow`).
- voxcmd: 19 TOML and 18 bash integrations in `home/voxcmd/.config/voxcmd/integrations/`, 22 in `integrations.d/`, each declaring `verbs` (regexes) and `[actions]` with a `run` line. `integrations/keybinds.toml` already runs any described bind by its desc (`hyprctl binds -j` in `integrations.d/keybinds.sh`). `tests/phrases.tsv` has 499 phrase rows.

So one action is declared up to three times: IPC function, Lua bind with its label, voxcmd verb with its run line.

**Proposal.** One JSON manifest of actions. Each entry: `id` (`zoom.toggle`), `label` (the bind desc and picker text), `key` (the default bind and submap), `params` (name, type, allowed values), `enabled` (a condition such as "bar running", or a command), and `run`: an IPC call (`target`, `function`), a dispatcher or a script. JSON, not TOML: Hyprland's Lua already has `lib/json.lua` and QML has `JSON.parse`; TOML would need a new parser in both. The IpcHandlers stay the transport; the manifest says which of their functions are public actions.

**How each surface consumes it.**
- Hyprland: a new `Bind.action(id, opts)` reads label, key and run from the manifest and calls `Bind.key`; `Submap.define` rows accept an id in place of key, action and desc. `Bind.key`, `Bind.unbind` and `Bind.submap` keep their signatures (public API for `custom/`). hyprvim needs no change: it reads descs from Hyprland, which now come from the manifest.
- voxcmd: a TOML action gains `action = "<id>"` in place of a `run` line, resolved by the Rust binary. Phrases stay in TOML; a phrase is how you say an action, not the action. The keybinds integration already reaches every action that has a key.
- Pickers: a command picker lists `enabled` actions by label; the keybinds picker can show the id.
- Shadow skill: `shadow.sh action <name> <id> [params]` resolves the id and makes the same IPC call `shadow.sh ipc` makes today, so agents drive actions by id.

**PRs, one surface at a time.**
- 1a: the manifest with a JSON schema and a handful of actions (zoom, screenshot, overview); a `registry` check step that validates it and fails a `run` naming a missing IPC function (reusing `qml_ipc.py`'s handler parser).
- 1b: `Bind.action` and one keymap file (`keymaps/global/tools.lua`) moved to it.
- 1c: the other global files, then the submaps through `Submap.define`.
- 1d: `qml-ipc` also fails a public handler function with no manifest entry (or an allow line).
- 1e: the command picker.
- 1f: `shadow.sh action`.
- 1g: voxcmd `action = "<id>"`, only after the port's 3.2 swap: before it, both the bash and the Rust voxcmd would need the feature.

**Checks.** A new `registry` step (scope `lua qml`, plus a `PATH_SCOPES` line for the manifest ahead of the `home/hypr/*` and Quickshell rules); `qml-ipc` grows the cross-check in 1d; `stylua` and `luacheck` cover `Bind.action`; the voxcmd suites and `phrases.tsv` cover 1g.

**Open questions (owner).**
- Where the manifest lives. It has to be stowed for Hyprland, Quickshell and voxcmd. Options: in the Quickshell tree (QML owns most actions), in `home/hypr/` (binds are the most entries), or in a small package of its own. Recommendation: a package of its own, so no consumer reaches into another's tree. Whether the greeter stages it (`lib/common/greeter-files.sh`) depends on whether lock actions are listed.
- Do `custom/` users override an action's key in the manifest, or only through `Bind.unbind` and `Bind.key` as today? Recommendation: as today.
- Is every handler function an action, or only the ones a person would call? Internal calls (`osd`, `cmdstatus refresh`) argue for "only some".

**Risks.** Moving binds can change which-key order or drop an option such as `submap_universal`. The voxcmd part waits on the port. Every new feature edits one more file.

## 2. Docs generated from code, with a drift check

**Scope.** `docs/keybinds.md` is a hand-written guide, not a list, so generate one section of it: a table of the shipped keys (key, submap, label, action id) between `BEGIN generated` and `END generated` markers, written from the manifest. The precedent is `theme/Style.qml`'s generated block, written by `scripts/gen-style-exports` and checked by the `style-exports` step.

**PRs.** 2a: the generator and a `docs-generated` step that regenerates and diffs, with a `scopes.py` rule sending the manifest and `docs/keybinds.md` to it. 2b: `QS/README.md`'s IPC table from the same manifest; `qml-ipc` then drops its table check.

**Checks.** New `docs-generated` step and its `PATH_SCOPES` lines; `lib/check/README.md` gets its line.

**Risks.** Before 1c the table lists only migrated binds; wait for 1c or say so. `custom/` binds are not in it, which is right for shipped docs.

## 3. AGENTS.md rules only, reasons in a decisions log

**Scope.** AGENTS.md is 23,610 bytes. Most of it is rules; the reasons behind past choices move to `specs/decisions.md`, one dated entry each (date from `git log -S` on the rule, or the move date when unknown), with the rule linking to it. Candidates, measured by reading the file:
- Overview: why systemd packages are stowed `--no-folding` (systemd ignores symlinked drop-in and `.wants` directories), and the `migrate-systemd` history. The rule left: "packages shipping systemd user units go in `NO_FOLD_PACKAGES` and are stowed with `just stow`".
- Commands: why branches cut before the runner port do not share passes.
- Hyprland config: the hyprwm/Hyprland#15040 reason behind `Bind.unbind`.
- Quickshell key conventions: why `Popups.after_close` (the focus hand-back).
- Global agent files and Gitignore: the "aggressive by design" explanation.

Kept inline: a one-clause reason that tells you when the rule applies. Reference material (installer file list, `just` recipes) is not this item.

**PRs.** 1, in one batch with 0a.

**Checks.** None new.

**Risks.** A rule lost in the move; review diffs rule lines before and after.

## 4. voxcmd port status out of AGENTS.md

**Scope.** AGENTS.md's second voxcmd paragraph is port status: the crate is not what runs yet, `VOXCMD_BIN=rs`, the goldens and their generators, `internal click-match` and friends, the click bridge's dump details, `_legacy-dump` and item numbers 2.3, 3.1 and 3.2. Move it to a tracked `specs/voxcmd-port.md`; AGENTS.md keeps the rules: test through `sandbox.sh`, add a phrase to `phrases.tsv`, regenerate goldens only with the owner's sign-off, run suites as check steps.

**Relation to `.planning/projects/voxcmd-port/voxcmd-port.md`.** That tracker (26,647 bytes, excluded through `.git/info/exclude`, not `.gitignore`) keeps session state: "Resume here", agents, lessons, owner-only and private items. It stays local. The tracked spec holds what a fresh clone needs: what runs today, how to run the Rust binary, the phase table (3.1 to 4.2) with statuses, the legacy-dump behaviour. The tracker links to the spec for phases instead of repeating them, so status has one home.

**PRs.** 1.

**Checks.** None new; `readme-links` covers the spec once 0b lands.

**Risks.** Nothing private may move into the public spec. Status lags if a port PR forgets the spec; add it to the tracker's per-PR checklist.

## 5. A short spec per new interactive surface

**Scope.** AGENTS.md "Interaction conventions" says: agree a new surface's keys, look and first run with the owner before building it. Make that a file: `specs/surfaces/<name>.md`, drafted from the template below, approved by the owner before the build PR. The build PR moves it into the feature folder as its README (`git mv`), so it becomes the feature doc and `readme-links` checks it from then on.

Template:

```markdown
# <Surface name>

Status: draft | approved <date> | built (<PR>)

## What it is for
Who opens it, from where, to do what.

## Keys
| Key | State | Does |
Follow AGENTS.md key conventions; name any departure.

## States
Each state (closed, list, prompt, error, empty), in and out.

## Config keys
| Key | Default | Where set (Settings pane, JSON file) |

## First run
What a new user sees; guided setup if a tool is needed.

## Acceptance checks
- [ ] Each key works in the shadow, with a screenshot per state.
- [ ] The registry actions it adds (item 1), with ids.
- [ ] The tests or table rows it adds (item 6).
```

**PRs.** 1: the template at `specs/surfaces/TEMPLATE.md` and the AGENTS.md sentence.

**Checks.** None.

**Risks.** Ceremony for small surfaces. Threshold: a spec for a new popup, picker, mode or skin; none for a row in an existing pane.

## 6. More executable specs

**Today.** The style already exists: `home/voxcmd/tests/phrases.tsv` (phrase, expected action, note), the voxcmd goldens in `home/voxcmd/tests/fixtures/*-goldens.tsv`, and `home/quickshell/tests/input_settings/vectors.tsv`, read by both a Lua and a JS runner.

**Areas that would gain** (candidates, not measured coverage):
- Popup and picker keys: key, state, expected action per surface, driven through the shadow; pins the key conventions, which no check reads today.
- Lock and greeter input: NORMAL/INSERT transitions of `Lock.key` and `Greeter.key` as key-sequence rows.
- voxcmd's `confirm_labels` (`integrations/keybinds.toml`): label and whether it asks first; the regexes are hard to read.
- The registry: action id, params, expected IPC call (reused by item 7).

**PRs.** One per area: a table, a runner, a Step and its `PATH_SCOPES` line.

**Risks.** Tables nobody reads; keep rows to cases that broke or a rule states.

## 7. One bad-input test across every command

**Scope.** For every manifest action with params, call it with adversarial values (empty, very long, wrong type, out of range, shell metacharacters, unknown enum) and require a clean error reply and a live bar afterwards: never a crash, a QML error or a hang. Modelled on photocraft's `panic_hunt`; values come from each action's `params`.

**PRs.** 7a: the runner against a throwaway `qs` instance (like the `json-store` and `polled-*` tests in `home/quickshell/tests/`) for actions that need no compositor. 7b: the rest through the shadow, which is isolated from the owner's screen.

**Checks.** A new `bad-input` step (needs `qs`, skip reason as the other runtime tests); the manifest's `PATH_SCOPES` line reaches it.

**Risks.** Side-effect actions (power, lock, screenshot) need a dry run or an isolated home, which the shadow gives. Slow; may need the serial lane.

## Open questions for the owner

1. Where the action manifest lives (item 1).
2. Which handler functions count as public actions (item 1).
3. Whether readme-links checks backticked paths in `specs/` plans (item 0).
4. The threshold for a surface spec (item 5).
