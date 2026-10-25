# Roadmap: specs, one command registry, generated docs

A plan only. Counts measured on main at 6a7ed8924 (2026-10-25). Items are in priority order; 3 and 4 are cheap and can ship first.

| #   | Item                                              | PRs (estimate) | Depends on      |
| --- | ------------------------------------------------- | -------------- | --------------- |
| 0   | docs/ vs specs/, plus local .plans/ and .logs/    | 2              | none            |
| G   | Global skill rules (orchestrator, handoff)        | 2              | 0a              |
| 1   | One command registry                              | 7              | none            |
| 2   | Docs generated from code, with a drift check      | 2              | 1a to 1c        |
| 3   | AGENTS.md rules only; decisions log               | 1              | 0a              |
| 4   | voxcmd port status out of AGENTS.md               | 1              | 0a              |
| 5   | A short spec per new interactive surface          | 2              | 5a 0a; 5b 1a    |
| 6   | More executable specs (tables, goldens)           | 1 per area     | none; one on 1a |
| 7   | One bad-input test across every command           | 2              | 7a none; 7b 1a, 1f |

Ship batches:
- B1 = 0a, 3, 4, 5a.
- B2 = G1, G2. They edit global skills, which the owner reads before merge, so they ship alone.
- B3 = 0b, 1a, 1b, 5b, 7a.
- B4 = 1c, 1d, then 2a. 2a merges after 1c, so its table lists every bind.
- B5 = 1e, 1f, 2b. B6 = 7b.
- 1g goes in the first batch after the voxcmd 3.2 swap. Item 6 PRs fit any batch.

Out of scope: parity scorecards, a large docs/ tree, a shared cross-repo rules or CI repo.

## Global vs this project

Global is the Claude setup in `home/claude/.claude/`, loaded in every repo, so it must hold in an unrelated project.

**Global** (item G):
- `.plans/` and `.logs/` replace the orchestrator scratch dir in the `orchestrator` and `orchestrator-handoff` skills; anything durable moves to tracked docs before they are deleted.
- Parallel briefs: "new work in a new file; only small edits to shared registries".
- Every fix ships a test that failed before the fix.

**This project:** the bad-input check (7); `enabled` returning a reason, not a bool (1); the generated-docs drift check (2); optional rising count floors (1); audience rules for `docs/` (0); the decisions log format (3).

**Skip:**
- A devlog: the trackers and handoff skill already do this.
- Scorecards, parity checklists, perf budgets: out of scope, no analogue here.
- Corpus pins, an mdBook: no corpus to pin; `docs/` stays small.
- A layering tool: `qml-layers` exists.
- Free-form params text: typed params can be checked and fuzzed.
- A flat mixed `docs/`: item 0's split avoids it.

## 0. docs/ vs specs/, and local .plans/ and .logs/

**Today.** `docs/` holds `keybinds.md` (204 lines) and `sounds.md` (128 lines), both user guides. Feature docs live beside the code (`QS/README.md`, 8 `features/*/README.md`, the Hyprland and voxcmd READMEs). Plans live in `.planning/` (in `.git/info/exclude`; 4 project folders and a `roadmap.md`, some spanning many sessions) and the orchestrator's scratch in `~/.cache/dotfiles/orch/` (200 files: PR bodies, commit drafts, review evidence).

**Scope.**
- AGENTS.md "Docs" rule: "`docs/` is for users: written for someone who has not read the code, leading with what to do. `specs/` is for agents and developers: the roadmap, durable plans, surface specs and the decisions log. A feature's README stays beside its code. Neither repeats a rule from this file; link to it." Moves: none; `docs/` fits. Items 3 to 5 add `specs/decisions.md`, `specs/voxcmd-port.md`, `specs/surfaces/`.
- `.plans/` and `.logs/` at the main checkout's root, for work in progress; they replace `.planning/` and absorb `~/.cache/dotfiles/orch/`. `specs/` is tracked and durable; these are local and temporary. AGENTS.md wording: "`.plans/<topic>.md` holds the plan for work in progress (drafts, batch order, open points); `.logs/<topic>/` holds its evidence (check output, review notes, PR bodies). Whoever owns the topic deletes both once it is merged or dropped, after moving anything durable (a decision, a status) into `specs/` in the last PR. They exist in the main checkout only; briefs give their absolute paths."
- Main checkout only, with absolute paths, over a copy per worktree: worktrees do not see ignored files, and one copy means everyone reads the same evidence. The orchestrator already briefs by absolute path; an agent without one finds the main checkout as the parent of `git rev-parse --path-format=absolute --git-common-dir`.
- `.gitignore` here, `.git/info/exclude` in the global skill. Here `/.plans/` and `/.logs/` go in `.gitignore`, so every clone and agent gets the rule and it is reviewed. The global skill cannot commit to an unrelated repo, so it falls back to `.git/info/exclude`. Git's standard excludes, which `readme-links` reads, honour both.
- What exists: `.plans/` replaces `.planning/` and `.logs/` absorbs the scratch. The cost is updating the skills (item G) and trackers that name the old paths.
- readme-links: `lib/check/steps/readme_links.py` reads only `*.md` under the Quickshell tree (`run_checks`), so `docs/` is unchecked today. Extend it to `docs/` and `specs/` for links and anchors, and add `"specs"` to `REPO_FOLDERS` (it lists `docs` already) so backticked `specs/` paths resolve. Check backticked paths in `docs/` and `specs/decisions.md`, not in plans, which name files that do not exist yet (this roadmap does).

**Dependencies.** None.

**PRs.** 0a: the AGENTS.md rules, the `.gitignore` lines, this file. 0b: readme-links over `docs/` and `specs/`, with cases in `lib/check/tests/test_readme_links.py`.

**Checks.** `readme-links` always runs ("tree" step) and `*.md` maps to scope `""`, so `scopes.py` is unchanged; its `lib/check/README.md` line changes.

**Risks.** Dead links in `docs/` surface; fix them in 0b. Local files never reach a reviewer; the move-to-`specs/` rule guards that. `git clean -X` deletes them.

## G. Global skill rules

**Scope.** In `home/claude/.claude/skills/orchestrator/SKILL.md` the "scratch dir" (reports, `codex-review.sh`) becomes `<main checkout>/.logs/<topic>/` and plan drafts go in `<main checkout>/.plans/`; `orchestrator-handoff/SKILL.md` reads trackers from `.plans/`, not `.planning/`. Step 5 gains the new-file sentence and the failed-before test rule.

**Dependencies.** 0a (this repo's rule and `.gitignore` lines come first).

**PRs.** G1: `.plans/` and `.logs/` in both skills, with the `.git/info/exclude` fallback. G2: the two brief sentences.

**Checks.** `agent-hooks` and `shfmt` cover touched skill scripts; every line must pass the AGENTS.md "Global agent files" test.

**Risks.** Moving paths mid-work strands a session's drafts; ship G1 between batches.

## 1. One command registry

**Today.** One action is declared up to three times:
- Quickshell: 22 `IpcHandler` files (appendix) with 102 `function` declarations, called from 72 tracked non-Markdown files. `qml-ipc` (`lib/check/steps/qml_ipc.py`) ties callers to handlers both ways.
- Hyprland: 7 `keymaps/global/*.lua` files call `Bind.*` from `lib/key/bind.lua` (76 call sites); 11 submaps use `Submap.define` row tables. Each bind has its own `desc` and action, often a `qs ipc` string; hyprvim (a separate repo) and the keybinds picker read the descs back.
- voxcmd: 19 TOML and 18 bash integrations in `integrations/`, 22 in `integrations.d/`, each with its own `run` lines. `integrations/keybinds.toml` already runs any bind by its desc. `tests/phrases.tsv` has 499 rows.

**Proposal.** One JSON manifest of actions, in its own stow package (`home/actions/`), so no consumer reaches into another's tree. Each entry: `id` (`zoom.toggle`), `label` (bind desc and picker text), `key` (default bind and submap), `params` (typed: name, type, allowed values), `enabled` and `run` (an IPC call, a dispatcher or a script). `enabled` returns a reason when the action is unavailable ("bar not running"), not a bool, so pickers and voxcmd can say why. JSON, not TOML: Hyprland's Lua has `lib/json.lua` and QML has `JSON.parse`; TOML needs a new parser in both. The IpcHandlers stay the transport; the manifest holds only person-facing functions. Internal plumbing (`osd`, `cmdstatus refresh`) is not an action; it is listed with a reason in `registry.allow`.

**No leaks around it.** A tracked bind whose action is not a manifest id, or a handler function with no entry, must be listed with a reason in `lib/check/registry.allow` (like `qml-ipc.allow`); a stale line fails. Otherwise additions grow around the registry, as photocraft's `menus.rs::is_live` ORs seven other sources.

**How each surface consumes it.**
- Hyprland: `Bind.action(id, opts)` reads label, key and run from the manifest and calls `Bind.key`; `Submap.define` rows accept an id. `Bind.key`, `Bind.unbind` and `Bind.submap` keep their signatures (public API for `custom/`). `custom/` overrides a key both ways: `Bind.unbind` and `Bind.key` as today, or `Bind.action(id)` to name the action (photocraft keys user shortcuts by command id); the manifest key stays the default. hyprvim needs no change: it reads descs from Hyprland.
- voxcmd: a TOML action gains `action = "<id>"` in place of a `run` line, resolved by the Rust binary. Phrases stay in TOML.
- Pickers: a command picker lists actions by label, greying out disabled ones with their reason.
- Shadow skill: `shadow.sh action <name> <id> [params]` makes the call `shadow.sh ipc` makes today, by id.

**Dependencies.** None to start. 1g waits for the voxcmd 3.2 swap: before it, both the bash and the Rust voxcmd would need the feature.

**PRs, one surface at a time.**
- 1a: the manifest, a JSON schema, a few actions (zoom, screenshot, overview); a `registry` step that validates it and fails a `run` naming a missing IPC function (reusing `qml_ipc.py`'s parser). The manifest sits at `home/actions/.config/actions/actions.json`, and `actions` goes in `packages/stow.ini` (or the `unstowed` list), which the `packages` step requires.
- 1b: `Bind.action`, and `keymaps/global/tools.lua` moved to it.
- 1c: the other global files, then the submaps.
- 1d: `registry.allow`, with the step failing unlisted binds and handler functions.
- 1e: the command picker. 1f: `shadow.sh action`. 1g: voxcmd `action = "<id>"`.

**Checks.** A new `registry` step (scope `lua qml`, with a `PATH_SCOPES` line for the manifest package and `registry.allow` ahead of the `home/hypr/*` and Quickshell rules); `stylua` and `luacheck` cover `Bind.action`; the voxcmd suites cover 1g. Optional: a floor the action count may not drop below ("never lower it"); low value.

**Risks.** Moving binds can change which-key order or drop an option such as `submap_universal`. Every new feature edits one more file. Whether the greeter must stage the manifest (`lib/common/greeter-files.sh`) depends on whether lock actions are listed.

## 2. Docs generated from code, with a drift check

**Scope.** `docs/keybinds.md` is a hand-written guide, so generate one section from the manifest: a table of shipped keys (key, submap, label, id) between `BEGIN generated` and `END generated` markers. Precedent: the generated block in `home/quickshell/.config/quickshell/theme/Style.qml`, written by `home/quickshell/.config/quickshell/scripts/gen-style-exports` and checked by the `style-exports` step.

**Dependencies.** 1a to 1c: before 1c the table would list only migrated binds.

**PRs.** 2a: the generator and a `docs-generated` step that regenerates and diffs. 2b: the `QS/README.md` IPC table from the same manifest; `qml-ipc` then drops its table check.

**Checks.** New `docs-generated` step, with `PATH_SCOPES` lines for the manifest and `docs/keybinds.md`, and its `lib/check/README.md` line.

**Risks.** `custom/` binds are not in the table; say so above it.

## 3. AGENTS.md rules only, reasons in a decisions log

**Scope.** AGENTS.md is 23,610 bytes. Reasons behind past choices move to `specs/decisions.md`, linked from the rule. Each entry: a date, the PR, and "chose X over Y because", plus any footgun. Date from `git log -S`, else the move date. Candidates:
- Overview: why systemd packages are stowed `--no-folding`, and the `migrate-systemd` history.
- Commands: why branches cut before the check-runner port do not share passes (the last sentence of the `just check` paragraph).
- Hyprland config: the hyprwm/Hyprland#15040 reason behind `Bind.unbind`.
- Quickshell key conventions: why `Popups.after_close` (the focus hand-back).
- Gitignore: the "aggressive by design" explanation.

Kept inline: a one-clause reason that tells you when the rule applies.

**Dependencies.** 0a. **PRs.** 1, in B1. **Checks.** None new.

**Risks.** A rule lost in the move; review diffs rule lines before and after.

## 4. voxcmd port status out of AGENTS.md

**Scope.** AGENTS.md's second voxcmd paragraph is port status: `VOXCMD_BIN=rs`, the goldens, `internal click-match` and friends, the click bridge, `_legacy-dump`, items 2.3, 3.1 and 3.2. Move it to a tracked `specs/voxcmd-port.md`; AGENTS.md keeps the rules: test through `sandbox.sh`, add a phrase to `phrases.tsv`, regenerate goldens only with the owner's sign-off, run suites as check steps.

**Relation to `.planning/projects/voxcmd-port/voxcmd-port.md`.** That local tracker (26,647 bytes) keeps session state ("Resume here", agents, lessons, private items) and stays local, in `.plans/` once item 0 moves it. The tracked spec holds what a fresh clone needs: what runs today, how to run the Rust binary, the phase table (3.1 to 4.2), the legacy dump. The tracker links to it, so status has one home.

**Dependencies.** 0a. **PRs.** 1. **Checks.** None new; `readme-links` covers the spec once 0b lands.

**Risks.** Nothing private may move into the public spec. Status lags if a port PR forgets the spec; add it to the tracker's per-PR checklist.

## 5. A short spec per new interactive surface

**Scope.** AGENTS.md "Interaction conventions" says: agree a new surface's keys, look and first run with the owner before building it. Make that a file, `specs/surfaces/<name>.md`, from the template below, approved by the owner before the build PR. The build PR moves it into the feature folder as its README (`git mv`), where `readme-links` checks it. A spec is needed for a new popup, picker, mode or skin; not for a row in an existing pane.

Format: Markdown with YAML front matter. A `surface-specs` check validates the front matter and the required headings (the template's six: What it is for, Keys, States, Config keys, First run, Acceptance checks); 5b adds that every id in `actions` exists in the registry. Keys are written `mod+z`. `status` is always required; `approved` is required once approved or built, `pr` once built; `actions` and `keys` may be empty lists.

```markdown
---
status: draft          # draft | approved | built
approved: 2026-10-25   # date; omit while draft
pr: 1234               # build PR; omit until built
actions: [zoom.toggle] # registry ids it adds (item 1)
keys: [mod+z]          # keys it adds
---
# <Surface name>

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
- [ ] The tests or table rows it adds (item 6).
```

**Dependencies.** 5a 0a; 5b 1a (the id check needs the registry). **PRs.** 5a, in B1: the template at `specs/surfaces/TEMPLATE.md`, the AGENTS.md sentence and the `surface-specs` step for front matter and headings. 5b, in B3: the action-id check. **Checks.** New `surface-specs` step (with a `PATH_SCOPES` line for `specs/surfaces/`), and its `lib/check/README.md` line. It covers only `specs/surfaces/`: on `git mv` the spec becomes a feature README the check never sees, so delete its front matter in that move (the status then lives in the PR).

**Risks.** Ceremony for small surfaces; the threshold above limits it.

## 6. More executable specs

**Today.** The style exists: `home/voxcmd/tests/phrases.tsv` (phrase, expected action, note), the voxcmd goldens in `home/voxcmd/tests/fixtures/*-goldens.tsv`, and `home/quickshell/tests/input_settings/vectors.tsv`, read by a Lua and a JS runner.

**Areas that would gain** (candidates, not measured coverage):
- Popup and picker keys: key, state, expected action, via the shadow; no check reads the key conventions today.
- Lock and greeter input: NORMAL/INSERT transitions of `Lock.key` and `Greeter.key` as key-sequence rows.
- voxcmd's `confirm_labels` (`integrations/keybinds.toml`): label and whether it asks first; the regexes are hard to read.
- The registry: action id, params, expected IPC call (reused by item 7).

**Dependencies.** None, except the registry table, which needs 1a. **PRs.** One per area.

**Checks.** Each area adds a Step with its `PATH_SCOPES` line; shadow-driven ones skip without the shadow's tools, like the other runtime tests.

**Risks.** Tables nobody reads; keep rows to cases that broke or a rule states.

## 7. One bad-input test across every command

**Scope.** Call every command with bad input and require a clean error and a live bar: no crash, QML error or hang. This goes further than photocraft's `panic_hunt`, which runs the same 4 fixed bad-param sets for every command (empty; zeros and 999999; huge and negative; empty arrays and strings) with a 4 s timeout: 7b derives values from each action's typed `params`. Two rules are copied:
- A timeout is rerun once before it fails, so a cold start is not a failure.
- Side-effect actions run as a dry run, chosen by id prefix (`power.`, `lock.`, `screenshot.`): given a dry-run flag where the handler has one, else skipped with the reason logged (panic_hunt's print rule).

**Dependencies.** 7a none: it reads the 102 IPC functions from `qml_ipc.py`'s handler parser. 7b needs 1a (typed params) and 1f (`shadow.sh action`).

**PRs.** 7a: generic param sets over every IPC function, against a throwaway `qs` (like `home/quickshell/tests/json_store/`). 7b: per-param values from the manifest, through the shadow for actions that need a compositor.

**Checks.** A new `bad-input` step (needs `qs`), scoped to the Quickshell tree and later the manifest.

**Risks.** A missed side-effect prefix makes a real call; 7a's throwaway instance and a broad starting list limit that. Slow; may need the serial lane.

## Inspiration

storytold/photocraft at 528491f (2026-10-25), a Rust image editor built by many contributors each driving an agent. Taken: one registry every surface iterates (`CommandSpec`), `enabled` with a reason, the bad-input sweep with its timeout and dry-run rules, local `plan/` and `log/`, checked generated docs, the decisions log format: small mechanisms that keep one fact in one place. Left: its large hand-kept docs, whose numbers drift, and the escape hatches around its registry.

## Appendix: IpcHandler files

Under `home/quickshell/.config/quickshell/`, one handler each: `features/*/<Name>Ipc.qml` for Sound, CommandStatus, Calendar, Brightness, Zoom, HyprvimPrompt, Picker, Lock, Notifications, Osd, Overview, TmuxOverview, Confirm, Popup, WhichKey, Power, Screenshot, Settings, Style, ClickHints and Weather, plus `theme/transitions/TransitionsIpc.qml`. A 23rd handler sits in `demo/overlay/shell.qml`.
