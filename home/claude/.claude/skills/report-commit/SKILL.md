---
name: report-commit
description: "Generate development activity reports from git commit history for a session or timeframe, grouped into problem-and-fix sections. Optional arguments: a timeframe (defaults to since the last session report) and a description of the work. Use when the user asks for a session report, commit history report, activity report, or /commit-report."
argument-hint: "[timeframe] [description]"
arguments:
  - args
---

# Commit Report

Argument string (optional): `$args`. It may include a timeframe and a work description.

A report tells someone who wasn't there what work was done in a session and why it mattered, in the order it happened. It is read by people billing, planning or reviewing the work, so it explains problems and outcomes, not just file changes.

## Timeframe

- If `$args` gives a timeframe (any git-compatible form: "today", "yesterday", "3 days ago", "2026-10-20"), use it.
- Otherwise use the modification time of the newest `session-report*.md` (`stat -c %y`), or "24 hours ago" if none exists.

## Gather the record

- Filter by **authored** date, not committed date. `git log --since` filters on the committed date, which a rebase, cherry-pick or merge resets to the day it happened, so old work would look new. List commits with `git log --all --author="$(git config user.name)" --since="<timeframe minus a margin>" --reverse --format='%aI %h %D%n%s%n%b'`, then keep the commits whose authored date (`%aI`) falls in the timeframe. Drop duplicates that are the same change on several branches (same subject and diff; `git patch-id` confirms).
- `--all` catches work on other branches and worktrees in the session. Note each commit's branch when that's useful context (for example, "on PR #54").
- Commit bodies carry the why (the problem found, the alternative rejected). Read them; headlines alone produce generic bullets.
- A later commit can replace the code an earlier message describes. Check every claim against the final diff. Describe a replaced approach only as the requirement the final code meets.
- Line counts: `git show --shortstat <sha>` per commit, or `git diff --shortstat <from>..<to>` for a contiguous range.
- Line counts cover source only. Exclude generated output: paths the repo lists as generated (for example `.claude/generated-paths`), minified `public/` output and `build: minify` commits. State source counts only.
- Uncommitted work: `git status --short` and `git diff --stat`. Mention it only if it's substantial, and label it as uncommitted.
- If the work happened in this conversation, the conversation is also part of the record: verification against live systems, configuration changes outside the repo (CMS or no-code builders, dashboards, infra), merges, rebases, deploys and PRs are work and belong in the report even when they produced no commit.

## Output

- Create or overwrite `session-report-<label>.md` at the repo root (`git rev-parse --show-toplevel`). The label is the start date of the timeframe (for example `2026-10-20`), so parallel runs do not overwrite each other.
- After writing, check `git check-ignore` on the file and tell the user if it would show up as untracked.

## Structure

```
[Title: Area or Theme: What This Session Achieved]

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
- Unrelated work streams in one session (two PRs, a tooling change) get separate sections, each with its own context.

### Writing

- Write as that session's own report, in the first person, as the person who did the work. No "initially", "first version" or references to other sessions.
- Active voice, past-tense verbs at the start of bullets: "Added", "Moved", "Gated", "Narrowed". Inside sentences, name the actor: "the code re-reads the record" or "I re-read the record", not "the record is re-read".
- Context paragraphs state the concrete problem, with the specific mechanism: "The SMS view only matches reviewed records and carries no Reviewer field, so the check could never see a pickup", not "the check didn't work properly".
- Name the identifiers a reader would search for: file paths, view and field keys, config names, PR numbers, SHAs.
- New code files: give the size in lines (`(73 lines)`). New assets: give the size in bytes and any format change (`(1.8KB)`, PNG → JPEG).
- Say how something was found when that was real work: "I tested…", "I checked every view against the live schema…".
- No filler, no hedging, no praise of the work. Keep each bullet to one or two lines.
- The report is client facing and used for billing. Describe each problem and its fix in the order it happened, in neutral, professional terms.
- Do not judge our own work. Avoid words such as "overengineered", "mistake", "wrong" and "broken by us".
- Write in the first person, as the person who did the work: "I added…", "I tested…". Do not refer to the person who directed the work ("the owner said", "the developer", "as requested").
- State a change of direction as the requirement it met. Write "Rebuilt the modal on Knack's own markup so Knack's stylesheet styles it", not "the first build was overengineered".

## Formatting

- `-` for bullets, a blank line after every heading, plain markdown that pastes cleanly into a spreadsheet cell or document.
- The title is the first line, without a `#`.
