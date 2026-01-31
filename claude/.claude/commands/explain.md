---
allowed-tools: Bash(cat:*), Bash(head:*), Bash(grep:*), Bash(git log:*), Bash(git diff:*), Bash(find:*), Bash(git branch:*), Bash(sed:*)
description: Explain the purpose, logic, and behavior of selected code files or line ranges
model: claude-haiku-4-5
---

## Context

- Current branch: !`git branch --show-current`
- Recent commits: !`git log -n 10 --oneline`

### If @filename(s) provided

- Show full contents: !`cat @ARGS`

### If @filename:line-range is provided (e.g., @src/index.ts:12-36)

- Extract relevant section: !`sed -n '12,36p' src/index.ts`

### If no files provided

- Show recent diffs: !`git diff HEAD~10`
- Show recently edited files: !`git show --name-only --pretty="" HEAD~10..HEAD`

## Your Task

1. Explain what the given code does, in plain language
2. Clarify logic, flow, and key variables or types
3. Describe how functions, classes, or side effects behave
4. Identify dependencies or assumptions
5. Provide a high-level summary for orientation

## Guidelines

- Keep language clear and beginner-accessible
- Use bullet points or paragraphs depending on complexity
- If unclear or ambiguous, ask clarifying questions in your response

## Output Format

- File/section reference
- What it does
- How it works (logic flow)
- Dependencies or caveats (if any)
