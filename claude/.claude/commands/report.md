---
allowed-tools: Bash(git log:*), Bash(git show:*), Bash(git diff:*), Bash(git diff --cached:*), Bash(git status:*), Bash(find:*), Bash(cat:*), Bash(grep:*)
description: Summarize recent project activity and in-progress work using natural timeframes
---

## Context

- Git log by time (default: today): !`git log --since="${ARGUMENTS:-today}" --oneline`
- Detailed changes: !`git show --stat --since="${ARGUMENTS:-today}"`
- Staged changes: !`git diff --cached --name-only`
- Unstaged changes: !`git diff --name-only`
- Untracked files: !`git status --short | grep "^??"`

### If @filename(s) or @filename:start-end are passed

- Show content: !`cat @ARGS`
- Show diff in file: !`git diff @ARGS`

## Your Task

1. Parse commit messages from the given timeframe
2. Categorize into:
   - Features (`feat:`)
   - Fixes (`fix:`)
   - Refactors (`refactor:`)
   - Tooling / infra (`chore:`, `build:`)
   - Docs or tests
3. Summarize staged and unstaged work
4. List untracked files
5. Format all of this into clean Markdown

## Output Format

# Dev Report

## ✅ Completed

### Features

- feat: ...

### Fixes

- fix: ...

### Refactors

- refactor: ...

### Infra / Tooling

- chore: ...

## 🚧 In Progress

### Staged changes

- <file>: <summary if available>

### Unstaged changes

- <file>: <summary if available>

### Untracked

- <file>
