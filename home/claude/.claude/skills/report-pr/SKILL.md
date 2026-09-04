---
name: report-pr
description: Generate concise development activity reports from a given GitHub pull request, in chronological order with proper markdown formatting. Requires a PR number or URL argument, plus an optional work description. Use when the user asks for a PR report, pull request report, or /pr-report.
argument-hint: "<pr-number-or-url> [description]"
arguments:
* args
---

# PR Report

Argument string: `$args` — must include a PR number or URL, and may include a work description.

## Context

Determine the PR from `$args` (number, `#123`, or full URL).

- PR metadata: `gh pr view <pr> --json title,body,commits,files,additions,deletions`
- Commit list on PR (chronological): `gh pr view <pr> --json commits --jq '.commits[] | .messageHeadline'`
- Full diff: `gh pr diff <pr>`
- Changed files with stats: `gh pr diff <pr> --name-only` and `git diff --stat <base>...<head>` when working in a local clone
- File sizes for new assets: `ls -lah` (when relevant)

### Arguments

`$args` must include:

1. **PR reference**: a PR number, `#number`, or PR URL
2. **Work Description** (optional): a brief description of the work accomplished (e.g., "PDF optimization and font improvements")

### Processing Logic

- If no description is provided, infer work description from the PR title, body, and commit history analysis.
- Treat the PR's commits as the chronological record, not repo-wide git log.

### Output Location

- Get current repo (if any): `git remote get-url origin`.
- Get PR's repo: `gh pr view <pr> --json url` (or from the PR URL directly).
- Current repo matches PR's repo: save as `pr-report.md` at repo root (`git rev-parse --show-toplevel`).
- No match, or not in a git repo: save as `~/Documents/Notes/work/pr-report.md` (create `~/Documents/Notes/work` if missing).

## Your Task

1. **Get the PR's commit history** in chronological order (oldest to newest)
2. **Analyze each commit** for:
   - Type of change (feat, fix, refactor, style, perf, chore)
   - Files affected and significance
   - Asset additions with file sizes
3. **Group related changes** into logical sections
4. **Create meaningful section titles** that describe the work accomplished
5. **Format output** for easy copy/paste into spreadsheet (title + markdown)
6. **Always create/overwrite pr-report.md** at the resolved output location (see Output Location) - Replace any existing pr-report.md file with the new report

## Analysis Guidelines

### Commit Categorization

- **Features** (`feat:`): New functionality, major additions
- **Fixes** (`fix:`): Bug fixes, corrections
- **Refactoring** (`refactor:`): Code restructuring without behavior change
- **Performance** (`perf:`): Optimization improvements
- **Styling** (`style:`): Code formatting, comments, documentation
- **Infrastructure** (`chore:`, `build:`, `ci:`): Tooling, build, deployment

### Asset Analysis

- For new files, include file sizes: `(1.8KB)`, `(37.6KB)`
- Note format changes: PNG → JPEG
- Identify optimization purposes

## Output Format

**Always overwrite/create `pr-report.md`** at the resolved output location with this structure:

```
[Descriptive Summary Title About Work Accomplished]

## [Section Name]

[Optional: context paragraph for complex changes]

- [Concise bullet point description]
- [Another change description]

## [Another Section]

[Optional: context paragraph for complex changes]

- [Concise bullet point description]
- [Another change description]

### [Subsection if needed]

- [Detailed points]
- [More details]

## Impact

[Optional: Brief summary of overall changes and their purpose if applicable]
```

## Formatting Requirements

- **Use `-` for bullet points** (not `•` or other symbols)
- **Add blank line after each heading**
- **Keep descriptions concise** but informative
- **No generic titles** - describe actual work accomplished
- **Chronological order** within sections (oldest to newest)
- **Group related commits** under logical section headings
- **Include file paths** when relevant for context

## Examples

Good section title: "End-of-Month Job Fix: Duplicate Record Prevention"
Bad section title: "Bug Fixes"

Good bullet: "Added MaterialIcons-TranscriptPDF.ttf font (1.8KB) for PDF size optimization"
Bad bullet: "Added font file"
