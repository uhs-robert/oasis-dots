# Roadmap: spec-driven design, one action registry

A plan only. Counts measured on main at 6a7ed8924 (2026-10-25).

## Goal

Spec-driven, spec-enforced design. Plain-English specs in `specs/` say what each feature must do, with no mention of Hyprland or Quickshell, so they can be tested through any tool. They are the permanent source of truth: they never move into READMEs, and the code's READMEs link to them. The main payoff is a guardrail against agent regressions (behaviour written down and tested); portability to another compositor or shell is secondary.

- **Scope.** Core specs first: keys, actions, bar, lock, notifications, as the system is today (codify; redesign later by changing a spec). Desktop behaviour only; packages, stow, services and the greeter stay scripts. Specs state behaviour, the look in words where it matters, and an optional reference screenshot. Features still being experimented with (styles, bar looks) stay spec-free until settled. Other features get a spec when touched.
- **Enforcement.** Each spec has numbered requirements (`BAR-03`). Phase 1: a check that every requirement has a test tagged with its id. Phase 2, gated: a given/when/then scenario runner (item 8).
- **Registry.** Tool-free actions (id, label, params, intent) with separate per-tool bindings, and one `oasis-djinn <id>` CLI that works anywhere inside the logged-in desktop session. Swapping tools rewrites bindings and, later, step functions only.
- **Authoring.** An agent drafts each core spec from the code; the orchestrator asks the owner only what the code cannot answer; the owner approves in the PR.

## Order

| #   | Item                                                | PRs | Depends on        |
| --- | --------------------------------------------------- | --- | ----------------- |
| 0   | docs/ vs specs/, plus local .plans/ and .logs/      | 2   | none              |
| G   | Global skill rules (orchestrator, handoff)          | 2   | 0a                |
| 1   | Spec format and requirement-to-test link check      | 2   | 0a                |
| 2   | One action registry and `oasis-djinn`               | 6   | none              |
| 3   | Core specs                                          | 5   | 1b, 2c            |
| 4   | Generated "bad params are rejected" tests           | 2   | 3b, 2a; 4b 2e     |
| 5   | Docs generated from code, with a drift check        | 2   | 2a to 2c          |
| 6   | AGENTS.md rules only; decisions log                 | 1   | 0a                |
| 7   | voxcmd port status out of AGENTS.md                 | 1   | 0a                |
| 8   | Scenario runner (gated)                             | n/a | 3, owner's call   |

Batches. The owner approves a batch's plan; its PRs merge when the reviewer and Codex are clean.
- B1 = 0a, 1a, 1b, 6, 7. Spec format and link check first; 6 and 7 are hygiene that blocks nothing.
- B2 = G1, G2. They edit global skills, which the owner reads before merge, so they ship alone.
- B3 = 0b, 2a, 2b.
- B4 = 2c, 2d, then 5a. 5a merges after 2c, so its table lists every bind.
- B5 = 2e, 5b.
- B6 = 3a (keys), 3b (actions).
- B7 = 3c (bar), 3d (lock), 3e (notifications).
- B8 = 4a, 4b. They tag the actions spec's requirement ids, so they follow 3b.
- 2f goes in the first batch after the voxcmd 3.2 swap.

Out of scope: parity scorecards, a large docs/ tree, a shared cross-repo rules or CI repo, specs for system setup.

## Global vs this project

Global is the Claude setup in `home/claude/.claude/`, loaded in every repo, so it must hold in an unrelated project.

**Global** (item G):
- `.plans/` and `.logs/` replace the orchestrator scratch dir in the `orchestrator` and `orchestrator-handoff` skills; anything durable moves to tracked docs before they are deleted.
- Parallel briefs: "new work in a new file; only small edits to shared registries".
- Every fix ships a test that failed before the fix.

**This project:** spec format and link check (1); the registry (2); generated-docs drift check (5); audience rules for `docs/` (0); the decisions log format (6).

**Skip:** a devlog (trackers and handoff do this); scorecards and perf budgets; an mdBook; a layering tool (`qml-layers` exists); free-form params text (typed params can be checked); a flat mixed `docs/`.

## 0. docs/ vs specs/, and local .plans/ and .logs/

**Today.** `docs/` holds `keybinds.md` and `sounds.md`, both user guides. Feature docs live beside the code (`QS/README.md`, 8 `features/*/README.md`, the Hyprland and voxcmd READMEs). Plans live in `.planning/` (in `.git/info/exclude`) and the orchestrator's scratch in `~/.cache/dotfiles/orch/` (200 files).

**Scope.**
- AGENTS.md "Docs" rule: "`docs/` is for users: written for someone who has not read the code, leading with what to do. `specs/` is for agents and developers: the roadmap, the specs, durable plans and the decisions log. A feature's README stays beside its code and links to its spec. Neither repeats a rule from this file; link to it." Items 1, 3, 6 and 7 add `specs/core/`, `specs/schema/`, `specs/gaps.md`, `specs/decisions.md` and `specs/voxcmd-port.md`.
- `.plans/` and `.logs/` at the main checkout's root, replacing `.planning/` and absorbing `~/.cache/dotfiles/orch/`. AGENTS.md wording: "`.plans/<topic>.md` holds the plan for work in progress (drafts, batch order, open points); `.logs/<topic>/` holds its evidence (check output, review notes, PR bodies). Whoever owns the topic deletes both once it is merged or dropped, after moving anything durable (a decision, a status) into `specs/` in the last PR. They exist in the main checkout only; briefs give their absolute paths."
- Main checkout only, with absolute paths: worktrees do not see ignored files, and one copy means everyone reads the same evidence. An agent without a path finds the main checkout as the parent of `git rev-parse --path-format=absolute --git-common-dir`.
- `/.plans/` and `/.logs/` go in this repo's `.gitignore` (every clone and agent gets the rule); the global skill cannot commit to an unrelated repo, so it falls back to `.git/info/exclude`.
- readme-links: `lib/check/steps/readme_links.py` reads only `*.md` under the Quickshell tree, so `docs/` is unchecked. Extend it to `docs/` and `specs/` for links and anchors, and add `"specs"` to `REPO_FOLDERS` so backticked `specs/` paths resolve. Check backticked paths in `docs/`, `specs/decisions.md` and the specs, not in plans, which name files that do not exist yet (this roadmap does).

**PRs.** 0a: the AGENTS.md rules, the `.gitignore` lines, this file. 0b: readme-links over `docs/` and `specs/`, with cases in `lib/check/tests/test_readme_links.py`.

**Checks.** `readme-links` always runs and `*.md` maps to scope `""`, so `scopes.py` is unchanged; its `lib/check/README.md` line changes.

**Risks.** Dead links in `docs/` surface; fix them in 0b. Local files never reach a reviewer; the move-to-`specs/` rule guards that. `git clean -X` deletes them.

## G. Global skill rules

**Scope.** In `home/claude/.claude/skills/orchestrator/SKILL.md` the "scratch dir" (reports, `codex-review.sh`) becomes `<main checkout>/.logs/<topic>/` and plan drafts go in `<main checkout>/.plans/`; `orchestrator-handoff/SKILL.md` reads trackers from `.plans/`. Step 5 gains the new-file sentence and the failed-before test rule.

**PRs.** G1: `.plans/` and `.logs/` in both skills, with the `.git/info/exclude` fallback. G2: the two brief sentences.

**Checks.** `agent-hooks` and `shfmt` cover touched skill scripts; every line must pass the AGENTS.md "Global agent files" test.

**Risks.** Moving paths mid-work strands a session's drafts; ship G1 between batches.

## 1. Spec format and requirement-to-test link check

**Scope.** A spec is Markdown at `specs/core/<id>.md`. Front matter is for machines to query and track state; it goes on specs (`specs/`) and plans (`.plans/`) only, and `docs/` user guides stay plain Markdown.

```markdown
---
id: bar                # = file name
title: Bar
status: draft          # draft | approved | implemented | deprecated
approved: 2026-10-25   # date; required once approved
prs: [1234]            # PRs that approved or changed it
implements: [home/quickshell/.config/quickshell/features/bar]  # code paths; their READMEs link back
depends_on: [actions]  # other spec ids
actions: [zoom.toggle] # registry ids
keys: [mod+b]
---
# Bar

## What it is for
Who uses it, from where, to do what.

## Requirements
- **BAR-01** One testable statement of behaviour, in plain words.
- **BAR-02** [gap: untested] A known gap is marked inline.

## Look
Described in words where it matters; optional screenshot.

## Not covered
Experimental or deliberately open parts.
```

Requirement ids live in the body only, one per line (spec prefix and number); front matter holds no requirement list. Requirements say what the user sees or can do, never a tool. Ids are never reused. Keys are written `mod+z`.

**Plan front matter** (`.plans/`): `kind` (tracker | plan | handoff), `status` (active | parked | done), `owner_session` (or none), `updated` (date), `specs` (spec ids it touches), `branch` (plan and handoff only, or none), `pr` (or none).

**Schemas.** Both are JSON Schema files written in YAML, in `specs/schema/` (`spec.yaml`, `plan.yaml`), validated by the repo check by `check-jsonschema`, added to `packages/` (`pipx.ini`) as a new dependency. The action registry (item 2) is validated in the same schema language. Editors get completion through yaml-language-server.

**Link check.** A `specs` step scans only `specs/core/*.md` (skipping `TEMPLATE.md`); `roadmap.md`, `decisions.md` and `voxcmd-port.md` carry no spec front matter. It validates each spec against its schema, that requirement ids match the file's prefix and are unique, and that every id appears as a tag in at least one test. The tag syntax (a `req: BAR-03` comment) is fixed in 1b, in the test styles that exist today: `lib/check/tests` Python cases, voxcmd and Quickshell `vectors.tsv` rows, shadow scripts. It also fails a tag naming a missing requirement. **Gaps** are tracked inline and committed: a requirement line may carry `[gap: untested]` or `[gap: unmet]`. The check fails an untested requirement unless it is marked `[gap: untested]`; a `[gap: unmet]` requirement needs no test tag. A generated `specs/gaps.md` lists every gap across specs, with a `docs-generated`-style drift check. Undecided questions found while drafting go to the owner and never become lasting gaps; there is no gaps folder and no local `.gaps/`. Untagged tests in a spec'd area are allowed: the check lists them as info and never fails on them. `actions` ids are checked against the registry once 2a lands.

**PRs.** 1a: the template at `specs/core/TEMPLATE.md`, the two schemas, the AGENTS.md sentence, and schema and heading checks. 1b: the requirement-to-test link check, and the generator for `specs/gaps.md` with its drift check.

**Checks.** New `specs` step, a `PATH_SCOPES` line for `specs/` and for the test folders it scans, and its `lib/check/README.md` line. Plans are local, so the plan schema is checked only when `.plans/` exists.

**Risks.** Tests that exist only to satisfy the tag; the owner's PR review of each spec guards that. Ceremony for small features; only core specs are required.

## 2. One action registry and `oasis-djinn`

**Today.** One action is declared up to three times:
- Quickshell: 22 `IpcHandler` files (appendix) with 102 `function` declarations, called from 72 tracked non-Markdown files. `qml-ipc` (`lib/check/steps/qml_ipc.py`) ties callers to handlers both ways.
- Hyprland: 7 `keymaps/global/*.lua` files call `Bind.*` from `lib/key/bind.lua` (76 call sites); 11 submaps use `Submap.define` row tables. Each bind has its own `desc` and action, often a `qs ipc` string; hyprvim (a separate repo) and the keybinds picker read the descs back.
- voxcmd: 19 TOML and 18 bash integrations in `integrations/`, 22 in `integrations.d/`, each with its own `run` lines. `integrations/keybinds.toml` already runs any bind by its desc. `tests/phrases.tsv` has 499 rows.

**Proposal.** A tool-free JSON manifest in its own stow package, `home/oasis-djinn/.config/oasis-djinn/actions.json`. Each action: `id` (`zoom.toggle`), `label` (bind desc and picker text), `params` (typed: name, type, allowed values), `intent` (one sentence of what it does), and `key` (one default plus optional extras). Per-tool bindings are separate: which Quickshell IPC call or Hyprland dispatcher or script performs the id. A tool swap rewrites the bindings, not the actions. No `enabled` field in v1; it arrives with the command picker later. JSON, not TOML: Hyprland's Lua has `lib/json.lua` and QML has `JSON.parse`.

`oasis-djinn <id> [params]` is the one CLI entry, usable from a terminal, the bar, a key or (later) voice, inside the logged-in desktop session only (not over SSH or across machines). Submaps list actions by id.

**All of it migrates.** Every tracked bind, submap row and person-facing IPC function becomes an action, early. Only internal plumbing (`osd`, `cmdstatus refresh`) stays out, listed with a reason in `lib/check/registry.allow` (like `qml-ipc.allow`); a stale line fails. Otherwise additions grow around the registry, as photocraft's `menus.rs::is_live` ORs seven other sources.

**How each surface consumes it.**
- Hyprland: `Bind.action(id, opts)` reads label and key from the manifest and calls `Bind.key`; `Submap.define` rows accept an id. `Bind.key`, `Bind.unbind` and `Bind.submap` keep their signatures (public API for `custom/`). `custom/` overrides a key both ways: `Bind.unbind` and `Bind.key` as today, or `Bind.action(id)` to name the action; the manifest key stays the default. hyprvim needs no change.
- voxcmd: a TOML action gains `action = "<id>"` in place of a `run` line, resolved by the Rust binary, which calls `oasis-djinn`. Phrases stay in TOML.
- Shadow skill: `shadow.sh action <name> <id> [params]` makes by id the call `shadow.sh ipc` makes today.

**Dependencies.** None to start. 2f waits for the voxcmd 3.2 swap, with no Bash interim.

**PRs.**
- 2a: the manifest, its JSON Schema (YAML, in `specs/schema/`), `oasis-djinn`, a few actions (zoom, screenshot, overview); a `registry` step that validates it and fails a binding naming a missing IPC function (reusing `qml_ipc.py`'s parser). `oasis-djinn` goes in `packages/stow.ini` (or the `unstowed` list), which the `packages` step requires.
- 2b: `Bind.action`, and `keymaps/global/tools.lua` moved to it.
- 2c: the other global files, the submaps, and the remaining person-facing IPC functions.
- 2d: `registry.allow`, with the step failing unlisted binds and handler functions.
- 2e: `shadow.sh action`. 2f: voxcmd `action = "<id>"`.

**Checks.** The `registry` step (scope `lua qml`, with a `PATH_SCOPES` line for the manifest package and `registry.allow` ahead of the `home/hypr/*` and Quickshell rules); `stylua` and `luacheck` cover `Bind.action`; the voxcmd suites cover 2f.

**Risks.** Moving binds can change which-key order or drop an option such as `submap_universal`. Every new feature edits one more file. The greeter may need the manifest staged (`lib/common/greeter-files.sh`) if lock actions are listed.

## 3. Core specs

**Scope.** One spec per area, in this order: keys, actions, bar, lock, notifications. Each describes the system as it is, in the item 1 format. The `actions` spec states the registry's behaviour (one action from any context, one default key plus extras, custom overrides). A feature's README gains a link to its spec.

**Authoring.** An agent drafts the spec from the code. The orchestrator asks the owner only what the code cannot answer. The owner approves in the PR; `status` becomes `approved` and the PR is added to `prs`. Each core-spec PR includes a pass over that area's existing tests, migrated by tagging, not rewriting: a test that proves a requirement gets its id tag and stays in its current framework; implementation tests (parsers, helpers) stay untagged; a test that disagrees with the draft is a conflict. Tooling tests (`lib/check`, install, hooks) are out of scope, and the voxcmd goldens come with voice later. A requirement with no test gets a new one in the same PR (runtime tests, the shadow, table rows), or is marked `[gap: untested]` or `[gap: unmet]` and lands in `specs/gaps.md`; a requirement that cannot be tested yet is rewritten or moved to "Not covered".

**Conflicts.** While drafting, a spec/test conflict becomes an owner question. Once a spec is approved the spec wins, and an intended behaviour change goes spec (owner-approved), then test, then code.

**Dependencies.** 1b (the check), 2c (so `actions` ids exist).

**PRs.** 3a to 3e, one per area.

**Risks.** Specs that bless today's accidents; the owner's review of each draft is the guard. Wrong scope: styles and bar looks being experimented with stay in "Not covered".

## 4. Generated "bad params are rejected" tests

**Scope.** No separate sweep tool. For each action, generate requirement-tagged tests from its `params`: out-of-range, wrong-type, empty and unlisted-value inputs must give a clean error and a live bar (no crash, QML error or hang). This goes further than photocraft's `panic_hunt`, which runs 4 fixed bad-param sets. Two rules are copied:
- A timeout is rerun once before it fails, so a cold start is not a failure.
- Side-effect actions (`power.`, `lock.`, `screenshot.`) run as a dry run where the handler has one, else are skipped with the reason logged.

**Dependencies.** 3b (the requirement ids they carry), 2a (typed params); 4b needs 2e.

**PRs.** 4a: generation for actions against a throwaway `qs` (like `home/quickshell/tests/json_store/`). 4b: actions that need a compositor, through the shadow.

**Checks.** A `bad-params` step (needs `qs`), scoped to the Quickshell tree and the manifest. Its tests carry the `actions` spec's requirement id.

**Risks.** A missed side-effect prefix makes a real call; the throwaway instance and a broad starting list limit that. Slow; may need the serial lane.

## 5. Docs generated from code, with a drift check

**Scope.** `docs/keybinds.md` is a hand-written guide, so generate one section from the manifest: a table of shipped keys (key, submap, label, id) between `BEGIN generated` and `END generated` markers. Precedent: the generated block in `home/quickshell/.config/quickshell/theme/Style.qml`, written by `scripts/gen-style-exports` and checked by the `style-exports` step.

**Dependencies.** 2a to 2c: before 2c the table would list only migrated binds.

**PRs.** 5a: the generator and a `docs-generated` step that regenerates and diffs. 5b: the `QS/README.md` IPC table from the same manifest; `qml-ipc` then drops its table check.

**Checks.** `docs-generated` step, with `PATH_SCOPES` lines for the manifest and `docs/keybinds.md`, and its `lib/check/README.md` line.

**Risks.** `custom/` binds are not in the table; say so above it.

## 6. AGENTS.md rules only, reasons in a decisions log

**Scope.** AGENTS.md is 23,610 bytes. Reasons behind past choices move to `specs/decisions.md`, linked from the rule. Each entry: a date, the PR, and "chose X over Y because", plus any footgun. Date from `git log -S`, else the move date. Candidates:
- Overview: why systemd packages are stowed `--no-folding`, and the `migrate-systemd` history.
- Commands: why branches cut before the check-runner port do not share passes.
- Hyprland config: the hyprwm/Hyprland#15040 reason behind `Bind.unbind`.
- Quickshell key conventions: why `Popups.after_close` (the focus hand-back).
- Gitignore: the "aggressive by design" explanation.

Kept inline: a one-clause reason that tells you when the rule applies.

**Dependencies.** 0a. **PRs.** 1, in B1. **Risks.** A rule lost in the move; review diffs rule lines before and after.

## 7. voxcmd port status out of AGENTS.md

**Scope.** AGENTS.md's second voxcmd paragraph is port status: `VOXCMD_BIN=rs`, the goldens, `internal click-match` and friends, the click bridge, `_legacy-dump`, items 2.3, 3.1 and 3.2. Move it to a tracked `specs/voxcmd-port.md`; AGENTS.md keeps the rules: test through `sandbox.sh`, add a phrase to `phrases.tsv`, regenerate goldens only with the owner's sign-off, run suites as check steps.

**Relation to the local tracker** (`voxcmd-port.md`, 26,647 bytes, in `.plans/` once item 0 moves it). The tracker keeps session state and stays local. The tracked spec holds what a fresh clone needs: what runs today, how to run the Rust binary, the phase table (3.1 to 4.2), the legacy dump. The tracker links to it.

**Dependencies.** 0a. **PRs.** 1. **Risks.** Nothing private may move into the public spec. Status lags if a port PR forgets it; add it to the tracker's per-PR checklist.

## 8. Scenario runner (gated)

Not scheduled. Build it only after 2 or 3 core specs use the link check and regressions still slip through it; the owner decides then. Requirements get given/when/then scenarios; a runner executes them, and its step functions (Quickshell and Hyprland via the shadow) are the only tool-specific code. Tests port one core area at a time; the generated bad-params tests become scenarios.

## Inspiration

storytold/photocraft at 528491f (2026-10-25), a Rust image editor built by many contributors each driving an agent. Taken: one registry every surface iterates (`CommandSpec`), the bad-input sweep with its timeout and dry-run rules, local `plan/` and `log/`, checked generated docs, the decisions log format. Left: its large hand-kept docs, whose numbers drift, and the escape hatches around its registry.

## Appendix: IpcHandler files

Under `home/quickshell/.config/quickshell/`, one handler each: `features/*/<Name>Ipc.qml` for Sound, CommandStatus, Calendar, Brightness, Zoom, HyprvimPrompt, Picker, Lock, Notifications, Osd, Overview, TmuxOverview, Confirm, Popup, WhichKey, Power, Screenshot, Settings, Style, ClickHints and Weather, plus `theme/transitions/TransitionsIpc.qml`. A 23rd handler sits in `demo/overlay/shell.qml`.
