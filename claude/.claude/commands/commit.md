---
allowed-tools: Bash(git add:*), Bash(git status:*), Bash(git commit:*), Bash(git branch:*), Bash(git log:*), Bash(git diff:*)
description: Create a conventional commit from current changes
---

## Context

- Status: !`git status`
- Branch: !`git branch --show-current`
- Recent: !`git log --oneline -10`
- Diff: !`git diff HEAD`

## Task

1. If no files are staged, stage all modified/new files (`git add`)
2. Analyze the diff and recent history
3. If multiple distinct logical changes exist, recommend splitting commits
4. For each commit:
   - Use **conventional commit** format
   - Keep first line ≤ 72 chars, imperative mood
   - Group related changes (code/docs/tests/etc)

## Format

Use:
`<type>: <description>`

Types:

- `feat`: new feature
- `fix`: bug fix
- `docs`: documentation
- `style`: formatting/style
- `refactor`: internal change
- `perf`: performance
- `test`: testing
- `chore`: tooling/build/meta

## Tips

- **Split by concern**: Different files, concerns, or change types
- **Be atomic**: One purpose per commit
- **Preview carefully**: Ensure message matches diff

## Good Examples

- `feat: add user auth system`
- `fix: resolve CI failure in deploy script`
- `docs: update API section for new endpoint`
- `refactor: simplify loop logic in parser`
- `style: reformat table layout with Tailwind`
- `chore: upgrade dependencies to latest versions`

## Notes

- Staged files = commit scope
- Nothing staged = auto-stage all
- Suggest multi-commit splits if appropriate
