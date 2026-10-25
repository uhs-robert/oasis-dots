# Roadmap: specs, one command registry, generated docs

A plan only. Counts measured on main at 6a7ed8924 (2026-10-25). Items are in priority order; 3 and 4 are cheap and can ship first.

| #   | Item                                              | PRs (estimate) | Depends on      |
| --- | ------------------------------------------------- | -------------- | --------------- |
| 0   | docs/ vs specs/, plus local plans/ and logs/      | 2              | none            |
| G   | Global skill rules (orchestrator, handoff)        | 2              | 0a              |
| 1   | One command registry                              | 7              | none            |
| 2   | Docs generated from code, with a drift check      | 2              | 1a to 1c        |
| 3   | AGENTS.md rules only; decisions log               | 1              | 0a              |
| 4   | voxcmd port status out of AGENTS.md               | 1              | 0a              |
| 5   | A short spec per new interactive surface          | 1              | 0a              |
| 6   | More executable specs (tables, goldens)           | 1 per area     | none; one on 1a |
| 7   | One bad-input test across every command           | 2              | 7a none; 7b 1a, 1f |

Ship batches:
- B1 = 0a, 3, 4, 5.
- B2 = G1, G2. They edit global skills, which the owner reads before merge, so they ship alone.
- B3 = 0b, 1a, 1b, 7a.
- B4 = 1c, 1d, then 2a. 2a merges after 1c, so its table lists every bind.
- B5 = 1e, 1f, 2b. B6 = 7b.
- 1g goes in the first batch after the voxcmd 3.2 swap. Item 6 PRs fit any batch.

Out of scope: parity scorecards, a large docs/ tree, a shared cross-repo rules or CI repo.

## Global vs this project

Each idea is sorted by where it lives. Global means the Claude setup in `home/claude/.claude/`, loaded in every repo, so it must hold in an unrelated project.

**Global** (item G):
- `plans/` and `logs/` replace the orchestrator scratch dir (today `~/.cache/dotfiles/orch/`) in the `orchestrator` and `orchestrator-handoff` skills, keeping the rule that anything durable moves to the repo's tracked docs in the last PR before the files are deleted.
- Parallel briefs: "new work goes in a new file; only small, surgical edits to shared registries". It reduces sibling conflicts.
- Every fix ships a test that failed before the fix.

**This project:**
- The bad-input check (item 7).
- The registry's `enabled` returns a reason, not a bool (item 1).
- The generated-docs drift check (item 2).
- Optional rising count floors (item 1).
- Audience rules for `docs/` in AGENTS.md (item 0).
- The decisions log format: dated, PR-linked, "chose X over Y because" (item 3).

**Skip:**
- A devlog: the trackers and the handoff skill already hand work between sessions.
- Scorecards, parity checklists, perf budgets: upkeep with no dotfiles analogue (out of scope).
- Corpus pins and an mdBook: no file corpus to pin, and `docs/` stays small.
- A layering tool: `qml-layers` already does this.
- Free-form params text: the manifest uses typed params, so they can be checked and fuzzed.
- A flat `docs/` mixing developer and user pages: it is what the split in item 0 avoids.

## 0. docs/ vs specs/, and local plans/ and logs/

**Today.** `docs/` holds `keybinds.md` (204 lines) and `sounds.md` (128 lines), both user guides. Feature docs live beside the code (`QS/README.md`, 8 `features/*/README.md`, the Hyprland and voxcmd READMEs). Plans live in `.planning/` (excluded through `.git/info/exclude`: 4 project folders and a `roadmap.md`; some trackers span many sessions, like the parked voxcmd port) and the orchestrator's scratch in `~/.cache/dotfiles/orch/` (200 files: PR bodies, commit drafts, review and check evidence).

**Scope.**
- AGENTS.md "Docs" rule: "`docs/` is for users: written for someone who has not read the code, leading with what to do. `specs/` is for agents and developers: the roadmap, durable plans, surface specs and the decisions log. A feature's README stays beside its code. Neither repeats a rule from this file; link to it." Moves: none; `docs/` fits. Items 3 to 5 add `specs/decisions.md`, `specs/voxcmd-port.md`, `specs/surfaces/`.
- `plans/` and `logs/` at the main checkout's root, for work in progress. `specs/` is tracked and durable; these are local and temporary. AGENTS.md wording: "`plans/<topic>.md` holds the plan for work in progress (drafts, batch order, open points); `logs/<topic>/` holds its evidence (check output, review notes, PR bodies). Whoever owns the topic deletes both once it is merged or dropped, after moving anything durable (a decision, a status) into `specs/` in the last PR. They exist in the main checkout only; briefs give their absolute paths."
- Main checkout only, with absolute paths, over a copy per worktree: worktrees do not see ignored files, and one copy means a reviewer and the orchestrator read the same evidence. The orchestrator already briefs by absolute path. An agent with no brief can find the main checkout with `git rev-parse --path-format=absolute --git-common-dir` (its parent).
- `.gitignore` here, `.git/info/exclude` in the global skill. In this repo, `/plans/` and `/logs/` go in `.gitignore`: every clone and every contributor's agent gets the rule, and it is reviewed like any rule. The global skill cannot commit to an unrelated repo, so where a repo has no such lines it adds them to `.git/info/exclude`, which needs no commit. Both are honoured by git's standard excludes, which `readme-links` reads.
- How they meet what exists. Recommendation: `plans/` replaces `.planning/` (move the folders, drop the exclude line) and `logs/` absorbs the scratch, one home for each; the cost is updating the skills (item G) and the trackers that name the old paths. Later, ship-batch can delete a merged topic.
- readme-links: `lib/check/steps/readme_links.py` reads only `*.md` under the Quickshell tree (`run_checks`), so `docs/` is unchecked today. Extend it to `docs/` and `specs/` for links and anchors, and add `"specs"` to `REPO_FOLDERS` (it lists `docs` already) so backticked `specs/` paths resolve. Check backticked paths in `docs/` and `specs/decisions.md`, not in plans, which name files that do not exist yet (this roadmap does).

**Dependencies.** None.

**PRs.** 0a: the AGENTS.md rules, the `.gitignore` lines, this file. 0b: readme-links over `docs/` and `specs/`, with cases in `lib/check/tests/test_readme_links.py`.

**Checks.** `readme-links` always runs ("tree" step) and `*.md` maps to scope `""`, so `scopes.py` is unchanged; its `lib/check/README.md` line changes.

**Risks.** Dead links already in `docs/` surface; fix them in 0b. Local files never reach another machine or a reviewer; the move-to-`specs/` rule is the guard. `git clean -X` deletes both folders.

## G. Global skill rules

**Scope.** In `home/claude/.claude/skills/orchestrator/SKILL.md`, the "scratch dir" (named for briefs, reports and `codex-review.sh`) becomes `<main checkout>/logs/<topic>/`, and plan drafts go in `<main checkout>/plans/`. `orchestrator-handoff/SKILL.md` reads trackers from `plans/` where it reads `.planning/` today. Step 5's parallel bullet gains the new-file sentence; its fixer bullet says the test must fail before the fix.

**Dependencies.** 0a (this repo's rule and `.gitignore` lines come first).

**PRs.** G1: plans/ and logs/ in both skills, with the `.git/info/exclude` fallback. G2: the two brief sentences.

**Checks.** `agent-hooks` and `shfmt` cover any skill scripts touched. Every line must pass the AGENTS.md "Global agent files" test (holds in an unrelated repo).

**Risks.** Moving paths mid-work strands a running session's drafts; ship G1 between batches, after the active trackers are moved.

## 1. One command registry

**Today.** One action is declared up to three times:
- Quickshell: 22 `IpcHandler` files (list in the appendix) with 102 `function` declarations, called from 72 tracked non-Markdown files, mostly voxcmd and Hyprland scripts. `qml-ipc` (`lib/check/steps/qml_ipc.py`) already ties callers to handlers both ways, with exceptions in `lib/check/qml-ipc.allow`.
- Hyprland: 7 `keymaps/global/*.lua` files call `Bind.*` from `lib/key/bind.lua` (76 call sites); 11 submaps use `Submap.define` row tables. Each bind has its own label (`desc`) and action, often a `qs ipc` string. hyprvim (a separate repo) and the keybinds picker read the descs back from Hyprland.
- voxcmd: 19 TOML and 18 bash integrations in `integrations/`, 22 in `integrations.d/`, each with its own `run` lines. `integrations/keybinds.toml` already runs any bind by its desc. `tests/phrases.tsv` has 499 rows.

**Proposal.** One JSON manifest of actions. Each entry: `id` (`zoom.toggle`), `label` (bind desc and picker text), `key` (default bind and submap), `params` (typed: name, type, allowed values), `enabled` and `run` (an IPC call, a dispatcher or a script). `enabled` returns a reason when the action is unavailable ("bar not running"), not a bool, so pickers and voxcmd can say why. JSON, not TOML: Hyprland's Lua has `lib/json.lua` and QML has `JSON.parse`; TOML needs a new parser in both. The IpcHandlers stay the transport; the manifest says which functions are public actions.

**No leaks around it.** An action outside the manifest must be listed in `lib/check/registry.allow` with a reason, as `qml-ipc.allow` does for handlers: a tracked bind whose action is not a manifest id, or a public handler function with no entry. A stale line fails. Without it, additions grow around the registry: photocraft's `menus.rs::is_live` ORs seven sources besides its registry.

**How each surface consumes it.**
- Hyprland: `Bind.action(id, opts)` reads label, key and run from the manifest and calls `Bind.key`; `Submap.define` rows accept an id. `Bind.key`, `Bind.unbind` and `Bind.submap` keep their signatures (public API for `custom/`). hyprvim needs no change: it reads descs from Hyprland.
- voxcmd: a TOML action gains `action = "<id>"` in place of a `run` line, resolved by the Rust binary. Phrases stay in TOML.
- Pickers: a command picker lists actions by label, greying out disabled ones with their reason.
- Shadow skill: `shadow.sh action <name> <id> [params]` makes the call `shadow.sh ipc` makes today, by id.

**Dependencies.** None to start. 1g waits for the voxcmd 3.2 swap: before it, both the bash and the Rust voxcmd would need the feature.

**PRs, one surface at a time.**
- 1a: the manifest, a JSON schema, a few actions (zoom, screenshot, overview); a `registry` step that validates it and fails a `run` naming a missing IPC function (reusing `qml_ipc.py`'s parser).
- 1b: `Bind.action`, and `keymaps/global/tools.lua` moved to it.
- 1c: the other global files, then the submaps.
- 1d: `registry.allow`, with the step failing unlisted binds and handler functions.
- 1e: the command picker. 1f: `shadow.sh action`. 1g: voxcmd `action = "<id>"`.

**Checks.** A new `registry` step (scope `lua qml`, with a `PATH_SCOPES` line for the manifest and `registry.allow` ahead of the `home/hypr/*` and Quickshell rules); `stylua` and `luacheck` cover `Bind.action`; the voxcmd suites cover 1g. Optional: a floor the action count may not drop below, raised by hand ("never lower it"); low value, so only if counts start slipping.

**Risks.** Moving binds can change which-key order or drop an option such as `submap_universal`. Every new feature edits one more file. Whether the greeter must stage the manifest (`lib/common/greeter-files.sh`) depends on whether lock actions are listed.

## 2. Docs generated from code, with a drift check

**Scope.** `docs/keybinds.md` is a hand-written guide, so generate one section: a table of shipped keys (key, submap, label, action id) between `BEGIN generated` and `END generated` markers, written from the manifest. Precedent: the generated block in `home/quickshell/.config/quickshell/theme/Style.qml`, written by `home/quickshell/.config/quickshell/scripts/gen-style-exports` and checked by the `style-exports` step.

**Dependencies.** 1a to 1c: before 1c the table would list only migrated binds.

**PRs.** 2a: the generator and a `docs-generated` step that regenerates and diffs. 2b: the `QS/README.md` IPC table from the same manifest; `qml-ipc` then drops its table check.

**Checks.** New `docs-generated` step, with `PATH_SCOPES` lines for the manifest and `docs/keybinds.md`, and its `lib/check/README.md` line.

**Risks.** `custom/` binds are not in the table, which is right for shipped docs but may surprise a user; say so above it.

## 3. AGENTS.md rules only, reasons in a decisions log

**Scope.** AGENTS.md is 23,610 bytes. Reasons behind past choices move to `specs/decisions.md`, linked from the rule. Each entry: a date, the PR, and "chose X over Y because", plus any footgun. Date from `git log -S`, else the move date. Candidates:
- Overview: why systemd packages are stowed `--no-folding`, and the `migrate-systemd` history. The rule left: units go in `NO_FOLD_PACKAGES`, stowed with `just stow`.
- Commands: why branches cut before the check-runner port do not share passes (the last sentence of the `just check` paragraph).
- Hyprland config: the hyprwm/Hyprland#15040 reason behind `Bind.unbind`.
- Quickshell key conventions: why `Popups.after_close` (the focus hand-back).
- Gitignore: the "aggressive by design" explanation.

Kept inline: a one-clause reason that tells you when the rule applies.

**Dependencies.** 0a. **PRs.** 1, in B1. **Checks.** None new.

**Risks.** A rule lost in the move; review diffs rule lines before and after.

## 4. voxcmd port status out of AGENTS.md

**Scope.** AGENTS.md's second voxcmd paragraph is port status: the crate is not what runs yet, `VOXCMD_BIN=rs`, the goldens and their generators, `internal click-match` and friends, the click bridge's dump details, `_legacy-dump`, items 2.3, 3.1 and 3.2. Move it to a tracked `specs/voxcmd-port.md`; AGENTS.md keeps the rules: test through `sandbox.sh`, add a phrase to `phrases.tsv`, regenerate goldens only with the owner's sign-off, run suites as check steps.

**Relation to `.planning/projects/voxcmd-port/voxcmd-port.md`.** That local tracker (26,647 bytes) keeps session state: "Resume here", agents, lessons, owner-only and private items. It stays local (in `plans/` once item 0 moves it). The tracked spec holds what a fresh clone needs: what runs today, how to run the Rust binary, the phase table (3.1 to 4.2) with statuses, the legacy-dump behaviour. The tracker links to the spec for phases, so status has one home.

**Dependencies.** 0a. **PRs.** 1. **Checks.** None new; `readme-links` covers the spec once 0b lands.

**Risks.** Nothing private may move into the public spec. Status lags if a port PR forgets the spec; add it to the tracker's per-PR checklist.

## 5. A short spec per new interactive surface

**Scope.** AGENTS.md "Interaction conventions" says: agree a new surface's keys, look and first run with the owner before building it. Make that a file, `specs/surfaces/<name>.md`, from the template below, approved by the owner before the build PR. The build PR moves it into the feature folder as its README (`git mv`), where `readme-links` checks it. A spec is needed for a new popup, picker, mode or skin; not for a row in an existing pane.

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

**Dependencies.** 0a. **PRs.** 1: the template at `specs/surfaces/TEMPLATE.md` and the AGENTS.md sentence. **Checks.** None.

**Risks.** Ceremony for small surfaces; the threshold above limits it.

## 6. More executable specs

**Today.** The style exists: `home/voxcmd/tests/phrases.tsv` (phrase, expected action, note), the voxcmd goldens in `home/voxcmd/tests/fixtures/*-goldens.tsv`, and `home/quickshell/tests/input_settings/vectors.tsv`, read by a Lua and a JS runner.

**Areas that would gain** (candidates, not measured coverage):
- Popup and picker keys: key, state, expected action per surface, driven through the shadow; pins the key conventions, which no check reads today.
- Lock and greeter input: NORMAL/INSERT transitions of `Lock.key` and `Greeter.key` as key-sequence rows.
- voxcmd's `confirm_labels` (`integrations/keybinds.toml`): label and whether it asks first; the regexes are hard to read.
- The registry: action id, params, expected IPC call (reused by item 7).

**Dependencies.** None, except the registry table, which needs 1a. **PRs.** One per area.

**Checks.** Each area adds a Step with its `PATH_SCOPES` line; shadow-driven ones skip without the shadow's tools, like the other runtime tests.

**Risks.** Tables nobody reads; keep rows to cases that broke or a rule states.

## 7. One bad-input test across every command

**Scope.** Call every command with bad input and require a clean error and a live bar: no crash, QML error or hang. This goes further than photocraft's `panic_hunt`, which runs the same 4 fixed bad-param sets for every command (empty; zeros and 999999; huge and negative; empty arrays and strings), each on a fresh session with a 4 s timeout. Here, 7b derives values from each action's typed `params` (wrong type, out of range, unknown enum, shell metacharacters). Two of its rules are copied:
- A timeout is rerun once before it fails, so a cold start is not a failure.
- Side-effect actions run as a dry run, chosen by id prefix (`power.`, `lock.`, `screenshot.`): passed a dry-run flag where the handler has one, otherwise skipped with the reason logged. panic_hunt does the same for its print commands.

**Dependencies.** 7a none: it reads the 102 IPC functions from `qml_ipc.py`'s handler parser. 7b needs 1a (typed params) and 1f (`shadow.sh action`).

**PRs.** 7a: generic param sets over every IPC function, against a throwaway `qs` (like `home/quickshell/tests/json_store/`). 7b: per-param values from the manifest, through the shadow for actions that need a compositor.

**Checks.** A new `bad-input` step (needs `qs`), scoped to the Quickshell tree and later the manifest.

**Risks.** A missed side-effect prefix runs a real power or lock call; 7a runs in a throwaway instance and the list starts broad. Slow; may need the serial lane.

## Open questions for the owner

1. Do `plans/` and `logs/` replace `.planning/` and absorb `~/.cache/dotfiles/orch/`, or coexist with them? Recommended: replace and absorb (items 0, G).
2. Where the action manifest lives: the Quickshell tree, `home/hypr/`, or a stow package of its own. Recommended: its own package, so no consumer reaches into another's tree (item 1).
3. Do `custom/` users override an action's key in the manifest, or only through `Bind.unbind` and `Bind.key` as today? Recommended: as today, and let `Bind.action` take an id from `custom/` too, so an override can name the action (photocraft keys user shortcuts by command id) (item 1).
4. Is every handler function an action, or only the ones a person would call? Internal calls (`osd`, `cmdstatus refresh`) argue for "only some" (item 1).

## Inspiration

storytold/photocraft, read at 528491f (2026-10-25), a Rust image editor built by many contributors each driving an agent. Taken: one registry every surface iterates (its `CommandSpec`), `enabled` with a reason, the bad-input sweep and its timeout and dry-run rules, local `plan/` and `log/` folders, checked generated docs, and the decisions log format. Each is a small mechanism that keeps one fact in one place. Left: its large hand-kept docs, whose numbers drift from the generated ones, and the escape hatches around its registry, which item 1's allow list prevents.

## Appendix: IpcHandler files

Under `home/quickshell/.config/quickshell/`, one handler each: `features/*/<Name>Ipc.qml` for Sound, CommandStatus, Calendar, Brightness, Zoom, HyprvimPrompt, Picker, Lock, Notifications, Osd, Overview, TmuxOverview, Confirm, Popup, WhichKey, Power, Screenshot, Settings, Style, ClickHints and Weather, plus `theme/transitions/TransitionsIpc.qml`. A 23rd handler sits in `demo/overlay/shell.qml`.
