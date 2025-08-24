---
allowed-tools: Bash(git log:*), Bash(git show:*), Bash(git diff:*), Bash(git diff --cached:*), Bash(git status:*), Bash(find:*), Bash(cat:*), Bash(grep:*), Bash(ls:*), Write(daily-report.md)
description: Generate concise development activity reports in chronological order with proper markdown formatting. Optional argument: description of work done (defaults to timeframe if not provided)
---

## Context

- Recent commits by time: !`git log --since="${TIMEFRAME:-24 hours ago}" --oneline --reverse`
- Detailed commit info: !`git log --since="${TIMEFRAME:-24 hours ago}" --stat --reverse`
- Current branch status: !`git status --short`
- Staged changes: !`git diff --cached --name-only`
- File sizes for new assets: !`ls -lah` (when relevant)

### Arguments

The command accepts an optional argument string that may include:

1. **Timeframe**: A git-compatible time format (e.g., "24 hours ago", "today", "yesterday", "3 days ago", "1 week ago")
2. **Work Description**: A brief description of the work accomplished (e.g., "PDF optimization and font improvements")

### Processing Logic

- If no timeframe is specified in arguments, default to "24 hours ago"
- If no description is provided, infer work description from git commit history analysis
- Arguments can contain both timeframe and description

### Timeframe Options

- Default: "24 hours ago"
- Alternative: "today", "yesterday", "3 days ago", "1 week ago"
- Custom: Any git-compatible time format

## Your Task

1. **Get commit history** in chronological order (oldest to newest)
2. **Analyze each commit** for:
   - Type of change (feat, fix, refactor, style, perf, chore)
   - Files affected and significance
   - Asset additions with file sizes
3. **Group related changes** into logical sections
4. **Create meaningful section titles** that describe the work accomplished
5. **Format output** for easy copy/paste into spreadsheet (title + markdown)
6. **Always create/overwrite daily-report.md** - Replace any existing daily-report.md file with the new report

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

**Always overwrite/create `daily-report.md`** with this structure:

```
[Descriptive Title About Work Accomplished]

## [Section Name]

- [Concise bullet point description]
- [Another change description]

## [Another Section]

[Optional context paragraph for complex changes]

### [Subsection if needed]

- [Detailed points]
- [More details]

## Impact

[Brief summary of overall changes and their purpose]
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

Good section title: "PDF Generation System Enhancement"
Bad section title: "Bug Fixes"

Good bullet: "Added MaterialIcons-TranscriptPDF.ttf font (1.8KB) for PDF optimization"
Bad bullet: "Added font file"
