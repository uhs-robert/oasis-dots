---
name: commit-messages
description: >-
  Write git commit messages with a Conventional Commits subject and a narrative, reasoning-focused body. Use when creating commits, drafting commit messages, or when the user asks for help writing a commit message.
---

# Commit Messages

Write commit messages that tell the story of _why_ a change was made, not just what changed. The reader should come away understanding the context, the decision, and the trade-offs.

## Subject Line

Format: `type(scope): imperative summary`, with `(#PR)` appended on a squash merge. Scope is optional.

- **Types**: `feat`, `fix`, `refactor`, `perf`, `docs`, `test`, `chore`, `build`, `ci`, `style`, `revert`.
- **Breaking changes**: add `!` after the scope (`feat(api)!: ...`) and a `BREAKING CHANGE:` footer.
- **Imperative mood**: "add", "fix", "remove", "prevent", "handle" -- never past tense.
- **Lowercase after the colon**, no trailing period, unless the repo's history clearly does otherwise.
- **Aim for 50 chars, hard cap 72.** Drop words the context already implies -- e.g. "add NOT NULL on" beats "add NOT NULL constraint on" because "NOT NULL" already means constraint. Don't repeat the scope in the summary.
- **Tickets go in the footer**, not the subject: `Refs: PROJ-123` or `Closes #42`.

Examples:

- `feat(export): show contact subscriptions in CSV`
- `test(cypress): fix flaky contact search spec`
- `refactor(api): remove unused field from payload (#123)`

## Body

Separate from subject with a blank line. Never hard-wrap: write each paragraph as one continuous line and let the viewer soft-wrap. Use backticks for code references (class names, method names, constants).

### Narrative Arc

Follow this structure (skip sections that aren't relevant for small changes):

1. **Context / current state**: What the world looks like before this change. Ground the reader.
2. **Problem or motivation**: What's wrong, missing, or desired. Name the specific concept or mechanism behind the problem rather than describing it loosely. "Not enforced at the DB level" is better than "the database didn't match" because it tells the reader exactly what kind of gap exists. Go further and name the real-world trigger -- the actors, behaviors, or patterns that made this change necessary _now_. "Customers hit this on every page reload" is stronger than "the cache can go stale" because it names who's affected and why it's urgent.
3. **Solution**: The approach or strategy, not a play-by-play of the diff. Describe the _shape_ of the change rather than enumerating files or functions. Use "This commit..." to demarcate from background.
4. **Design reasoning**: Why this approach. State constraints or principles, discuss alternatives considered. Connect facts to the specific concerns they address -- "the table is small" is an assertion; "the table is small enough that the lock will be near-instant" is reasoning. The reader shouldn't have to infer why a fact matters.
5. **Scope boundaries**: What's explicitly _not_ included. Use phrases like "out of scope for this change" or "a follow-up will..."
6. **Incidental discoveries**: Anything found along the way. "While digging into this, I discovered..."
7. **Future work**: What should happen next, if anything.
8. **Living with this change**: When a change introduces a new constraint, convention, or tool, include practical guidance for developers who'll encounter it. What should they do when it gets in their way? When is it appropriate to override or work around it? This is distinct from future work -- it's a playbook for coexisting with the change.

### Voice and Tone

- **First person**: "I chose to", "I considered", "My philosophy was". The author is present in the narrative.
- **Conversational but precise**: Reads like explaining the change to a colleague over coffee, not like formal documentation.
- **Length tracks reasoning, not diff size**: A complex redesign gets section headers, diagrams, and benchmarks. But a subtle one-line bug fix that took days to hunt down can also warrant a page-long explanation tracing the investigation. Write as much as the _reasoning_ demands, regardless of how many lines changed.

### Enrichment (use when relevant)

- **Section headers**: For long messages, use markdown-style headers (`Performance`, `Security`, `Notable choices`, etc.) with underlines or blank-line separation.
- **Cross-references**: Cite commit SHAs, PR numbers, Sentry links, or documentation URLs. The reader should be able to trace anything. Only reference durable artifacts — planning documents, conversation context, and internal phase labels (e.g. "Phase 1") don't survive into git history.
- **Existing conventions**: When the change follows an existing codebase pattern, name it ("following the pattern used by similar validation rules"). This orients the reader without requiring them to read other files.
- **Principles/constraints**: Before describing a solution, state the constraints that guided it as a numbered list.
- **Alternatives considered**: "I considered X but it broke constraint Y. Eventually I settled on Z."
- **Code snippets / payload shapes**: Include when they clarify the change (JSON shapes, SQL, small code examples).
- **Mermaid diagrams**: For complex control flow, show before/after as flowcharts or state diagrams.
- **Performance data**: Include benchmarks or query plan comparisons when the change has performance implications.
- **Security implications**: Call out security improvements even when they're a side effect.
- **Deployment safety**: Note whether the change is safe to deploy at any time, requires ordering, or is behind a feature flag. "This change was written to be safe to deploy any time."
- **Verification**: Describe how you confirmed the change works. "I verified this by...", "I was able to reproduce the error using..."
- **ENV variables**: When introducing new environment variables, list them explicitly.
- **State combinatorics**: For UI work, document the space of possible states (e.g. with TypeScript ADTs or a count of combinations).

### Footers

Trailers go last, after a blank line, one per line: `Refs: PROJ-123`, `Closes #42`, `BREAKING CHANGE: <what breaks and how to migrate>`, `Co-authored-by: ...`.

### Recurring Phrases and Conventions

These signal phrases appear naturally and serve specific roles:

- "This commit..." -- demarcates what the diff does vs. background.
- "Note that..." -- adds caveats the reader should be aware of.
- "While digging into this, I discovered..." -- incidental findings.
- "out of scope for this change" -- explicit scope boundary.
- "I've already spent my refactoring budget" -- scope discipline.
- "This is purely a refactor" or "pure refactor (ish)" -- declares no behavior change, sometimes with noted small exceptions.
- "A follow-up will..." -- promises future work without blocking now.
- "Longer-term, we probably want to..." -- non-blocking future vision.

## Examples

### Small fix

```
fix(integrations): correct ExampleService constant typo

While browsing the code I discovered a typo in the ExampleService API. A constant was written as `Inte::ExampleService` rather than `Integrations::ExampleService`.
```

### Bug fix

```
test(contacts): fix flaky contact search spec (#234)

The contact search spec can flake when generated names for the "match" and "non-match" contacts happen to overlap. This hard-codes the names for this specific test and removes generated names from the factory.

Refs: PROJ-456
```

### Feature with design reasoning

```
feat(export): show contact subscriptions in CSV

Currently we don't show subscription data for archived contacts in the CSV export because the association we use only returns active contacts. We want to show all subscriptions associated with the contact that are accessible to the user.

I wanted to maintain 3 principles:

1. Permission logic stays in the permission layer
2. No N+1: subscription data must be batch-loadable
3. Serializer is active/archived-contact agnostic

I considered a variety of solutions but they kept breaking one or more of these constraints. Eventually I settled on a solution that worked like this:

- DB view aggregates subscription IDs as an array on each record. This is structural, no permission logic applied.
- Permission layer filters by tenant ID.
- Manual pre-loading of subscription IDs avoids N+1

Refs: PROJ-123
```

### Refactor with before/after

```
refactor(session): restructure session service tree

In the spirit of "make the change easy, then make the easy change", this commit re-structures the entire tree of services into a form that better suits the changes we're about to make.

Pure refactor (ish)
-------------------

This is mostly a pure refactor, with a couple small exceptions...

[... sections with mermaid diagrams showing before/after flow ...]

Refs: PROJ-789
```

### Breaking change

```
feat(api)!: rename /v1/orders to /v1/checkout

The orders endpoint now handles payment as well as cart state, and the old name kept sending integrators to the wrong docs. This commit renames the route and leaves a 410 stub behind so stale clients fail loudly instead of silently posting to nothing.

BREAKING CHANGE: clients on /v1/orders must migrate to /v1/checkout before 2026-06-01.
```

### Incremental Rollout Pattern

For risky or large changes, commit messages document a deliberate incremental strategy:

1. Add nullable column / feature-flagged code (safe to deploy anytime)
2. Backfill existing data or enable flag
3. Make column non-nullable / remove flag (only after step 2 is done)

Each commit explains where it sits in the sequence: "Now that we've cleaned up the existing API keys, we can safely add the stricter constraints everywhere."

### Incident Chain Narrative

When fixing bugs introduced by earlier commits, tell the chain story:

```
fix(cleanup): stop over-selecting archived records

In abc12345..., we started moving away from archived records. Then we tried to rein it back in with def67890..., but this is subject to the default scope again. This commit adds thorough testing to ensure we neither *over* select nor *under* select records to delete.
```

## Anti-Patterns

- "update files" or "various fixes" -- say what actually changed.
- Starting the body with what the commit does rather than why.
- Passive voice ("it was decided") -- use "I chose" or "we decided".
- Explaining what the diff shows -- the reader can see the diff. Explain the _reasoning_ behind it.
- Including coordination notes for the current team ("go talk to X about the credentials", "we need to follow up in Slack") -- commit messages are for future readers, not present-day task management.
- Picking the type by file touched instead of by intent -- a test-only change is `test`, a bug fix that touches tests is still `fix`.
- Ticket IDs in the subject -- put them in the footer.

## Workflow

When asked to commit:

1. Read the diff carefully.
2. Identify the _story_: what was the state before, what changed, why.
3. Pick the type and scope by intent; use the scope names the repo's history already uses.
4. Draft the subject in imperative mood, under 72 chars.
5. Write body following the narrative arc, one line per paragraph.
6. Add enrichment (cross-refs, diagrams, benchmarks) where it helps, then footers.
