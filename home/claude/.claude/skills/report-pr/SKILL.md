---
name: report-pr
description: Generate development activity reports from a GitHub pull request, grouped into problem-and-fix sections, optionally split into one report per work session or date range. Requires a PR number or URL argument, plus an optional work description and split point. Use when the user asks for a PR report, pull request report, a report for part of a PR's work (e.g. "just today's work"), or /pr-report.
argument-hint: "<pr-number-or-url> [description] [--split <date>[,<date>...]] [--since <date>] [--until <date>]"
arguments:
* args
---

# PR Report

Argument string: `$args`. It must include a PR number or URL, and may include a work description and a date range or split points.

A report tells someone who wasn't there what work was done and why it mattered, in the order it happened. It is read by people billing, planning or reviewing the work, not by the code reviewer, so it explains problems and outcomes, not just file changes.

## Gather the record

Determine the PR from `$args` (number, `#123`, or full URL).

- Commits with **authored** dates and full messages: `gh pr view <pr> --json commits --jq '.commits[] | "\(.authoredDate) \(.oid[0:7]) \(.messageHeadline)\n\(.messageBody)\n"'`. Use authored dates, never committed dates: a rebase or merge rewrites committed dates to the day it happened, so every commit looks like it was done that day.
- Commit bodies carry the why (the problem found, the alternative rejected). Read them; headlines alone produce generic bullets.
- The diff, per range: `gh pr diff <pr>`, or in a local clone `git diff --stat <from>..<to>` and `git diff --shortstat <from>..<to>` for line counts per period.
- Related work outside the PR: commits on the base branch that reference the PR or its issue (`git log --all --grep '#<pr>' --grep '#<issue>'`). Include them, marked as going straight to the base branch, with their short SHAs.
- The PR body and review comments can be stale or describe an earlier approach. Check claims against the final code before repeating them.
- If the work happened in this conversation, the conversation is also part of the record: verification against live systems, configuration changes outside the repo (CMS or no-code builders, dashboards, infra), merges, rebases and deploys are work and belong in the report even when they produced no commit.

## Splitting by session or date

When `$args` or the user asks for part of the work ("before today", "just this session", `--split`, `--since`, `--until`):

- Partition commits by authored date. A split date starts the later period.
- Write one report per period, each standing alone: its own title, sections, impact and line counts for that period's range only.
- Write each period as that session's own report, in the voice of someone reporting what they did in that session. Do not frame an earlier period as "initial", "first version" or "previously", and do not refer to the other period.
- Name the files `pr-report-1-<label>.md`, `pr-report-2-<label>.md`, …, with short labels such as `previous` and `today`. Without a split, use `pr-report.md`.

## Output location

- Compare `git remote get-url origin` with the PR's repo (`gh pr view <pr> --json url`).
- Same repo: save at the repo root (`git rev-parse --show-toplevel`). Otherwise, or outside a repo: save under `~/Documents/Notes/work/` (create it if missing).
- Always create or overwrite. After writing, check `git check-ignore` on each file and tell the user if any report would show up as untracked.

## Structure

```
[Title: Feature or Area: What This Work Achieved]

## [Section named after the work, e.g. "Recall Check Using the Right Data Source"]

[Context paragraph: the problem found and why it mattered, when it isn't obvious from the bullets.]

- [What was done, naming the concrete file, view, field, endpoint or setting]
- [Another change]

## Impact

[What users or the team can do now that they couldn't before; what risk is gone. Then the numbers: lines added/removed across N files. Then anything the work depends on outside the repo.]
```

### Grouping

- Group commits by the problem they solve, not by commit type. "Reviewer Race Conditions Found in Testing" beats "Bug Fixes".
- Order sections chronologically by when the work started, and bullets chronologically within a section.
- Fold fix-ups, renames and review follow-ups into the section of the work they adjust. They get their own section only if substantial; trivial ones go in a closing "Cleanup, Merge and Release" style section, or nowhere.

### Writing

- Active voice, past-tense verbs at the start of bullets: "Added", "Moved", "Gated", "Narrowed". Inside sentences, name the actor: "the code re-reads the record", not "the record is re-read".
- Context paragraphs state the concrete problem, with the specific mechanism: "The SMS view only matches reviewed records and carries no Reviewer field, so the check could never see a pickup", not "the check didn't work properly".
- Name the identifiers a reader would search for: file paths, view and field keys, config names, SHAs for out-of-PR commits.
- New code files: give the size in lines (`(73 lines)`). New assets: give the size in bytes and any format change (`(1.8KB)`, PNG → JPEG).
- Say how something was found when that was real work: "Testing showed…", "I checked every view against the live schema…".
- No filler, no hedging, no praise of the work. Keep each bullet to one or two lines.

## Formatting

- `-` for bullets, a blank line after every heading, plain markdown that pastes cleanly into a spreadsheet cell or document.
- The title is the first line, without a `#`.
