---
allowed-tools: Bash(find:*), Bash(git log:*), Bash(cat:*), Bash(head:*), Bash(git diff:*), Bash(git branch:*)
description: Analyze this codebase for performance or architectural inefficiencies
---

## Context

- Current branch: !`git branch --show-current`
- Recent commits: !`git log -n 20 --oneline`

### File Targeting

- If invoked with `@filename`, limit analysis to the given file(s)
- If no file is referenced, analyze the entire repo:

```bash
find . -type f \
  -not -path "*/.git/*" \
  -not -path "*/node_modules/*" \
  -not -name "*.lock" \
  -not -name "*.png" \
  -not -name "*.jpg" \
  -not -name "*.svg" \
  -not -name "*.env" \
  -not -name "*.zip" | head -n 100
```

## Your Task

1. Review the full context of the codebase or referenced files.
2. Identify bottlenecks or inefficiencies in:
   - Execution speed
   - Memory usage
   - IO (network, filesystem, database)
   - Code structure, flow, or duplication
3. Propose targeted optimizations:
   - Show the relevant line or file region
   - Explain what's inefficient or risky
   - Suggest a concrete, improved pattern or strategy

## Guidelines

- Prefer high-impact suggestions over nitpicks
- Use plain language with optional pseudocode or examples
- Do not recommend premature micro-optimizations
- Include file/line numbers if available for clarity
- Be language-aware (JS/TS, Python, Go, etc.)

## Example Output

- File: `src/utils/math.ts`
  Problem: Inefficient recursive call for Fibonacci
  Suggestion: Replace with memoized or iterative version

- File: `app/index.js`
  Problem: Blocking call inside render
  Suggestion: Move expensive operation to `useEffect()` with loading fallback

- File: `api/user.ts`
  Problem: Multiple sequential DB calls
  Suggestion: Batch with a single SQL query or use parallel Promise.all
