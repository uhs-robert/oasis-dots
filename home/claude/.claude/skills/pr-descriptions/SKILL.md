---
name: pr-descriptions
description: >-
  Write pull request titles and bodies that are short, human and reviewer-focused. Use when opening a PR (`gh pr create`), editing a PR's title or description, or when the user asks for help writing one.
---

# PR Descriptions

A PR body is for the reviewer reading it today. The commit messages carry the full reasoning for future readers; the body gives the reviewer what they need to review and merge safely, and nothing else. Aim for under 150 words.

## Title

The Conventional Commits subject of the change, written by the `commit-messages` rules: `type(scope): imperative summary`. On a single-commit PR, reuse the commit subject. On a multi-commit PR, write the subject the squashed commit would get.

## Body

Plain paragraphs, in this order, skipping any that have nothing to say:

1. **Why.** The problem or trigger, in a sentence or two. If an issue already explains it, link the issue and say only what the issue doesn't.
2. **What changed.** The shape of the change in prose, not a file-by-file tour. Name commands, flags and files in backticks where the reviewer will look for them.
3. **What a reviewer would miss.** Merge order, a stacked base, something to do after merging (restow, migrate, rerun an install), a behavior that stayed the same on purpose, something dropped from an earlier version of the PR.
4. **How it was checked**, only when that is not obvious from the diff and CI: a live test, a manual repro, a case the tests can't reach. One line.
5. **Issue link**, last, on its own line: `Closes #N`, or `Part of #N` while other PRs for that issue remain.

On a stacked PR, the first line is `Stacked on #N.`

## Style

- First person, plain and specific: "I dropped the chained-merge hook", not "The chained-merge hook has been removed".
- No headings unless there are genuinely 3+ distinct sections. A short PR never has them.
- No bold-label bullet inventories (`- **Cleanup:** ...`). If the change has several independent parts, a plain bullet per part is fine; prefer prose for one or two.
- No preamble explaining scope ("This PR does the following..."), no summary of the issue, no "Verification" or "Testing" section for routine checks, no attribution lines.
- Don't restate the diff. The reviewer has it; tell them what the diff can't.

## Example

```
fix(quickshell): show keyd's remaps in Settings, drop the Caps Lock toggle

Settings > Keyboard's "Caps Lock as Escape" set an XKB option, but keyd (always installed) remaps Caps Lock below Hyprland, so the toggle did nothing either way, and keyd's own remaps appeared nowhere.

The toggle and `caps_escape` are removed. The Keyboard section now reads `/etc/keyd/default.conf` and shows each `[main]` remap as a read-only row; Enter on Tab lists the vim layer's keys. Rows hide when keyd isn't running.

Closes #610
```

## Anti-patterns

- A `## Summary` / `## Changes` / `## Test plan` template filled in for a 20-line change.
- Bullet-per-file change lists.
- Pasting the commit message body. The PR body is shorter and aimed at the reviewer.
- Coordination chatter that won't matter once merged ("ping me when...") belongs in a comment, not the body.
