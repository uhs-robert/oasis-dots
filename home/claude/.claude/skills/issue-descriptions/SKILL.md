---
name: issue-descriptions
description: >-
  Write GitHub issue titles and bodies that state a problem and its impact, short and human. Use when opening an issue (`gh issue create`), editing one, filing a follow-up or tracking issue, or when the user asks for help writing one.
---

# Issue Descriptions

An issue says what is wrong or missing and why it matters, so whoever picks it up can choose the fix. It is not an implementation plan: the approach is decided in the PR, where the code is. Aim for under 150 words.

Write every sentence by the `plain-writing` skill. This skill sets the structure and the length.

## Title

`Area: the problem`, in plain words, not Conventional Commits. Name the symptom or the missing capability, not the fix.

- `Settings: Caps Lock toggle does nothing under keyd, and keyd's remaps are invisible`
- `Wallpaper: pin images per monitor and toggle automatic rotation`

## Body

Plain paragraphs:

1. **The problem.** The current state and what goes wrong, concretely: who hits it, when, and what it costs them. Name the mechanism if it is known ("keyd acts below Hyprland, so the XKB option has no effect").
2. **Evidence**, when there is any: exact error text, a repro command, the PR or session where it showed up. Keep logs to the lines that matter.
3. **The outcome wanted.** One or two sentences in "must" form that describe behavior, not code: "Settings must show what keyd does, read from its config." Constraints that any fix must respect go here too ("survive hotplug", "apply without restarting anything").

## Style

- First person where it helps, plain and specific.
- No headings, no bold-label bullets, no checklists of steps to implement.
- Do not name files to edit or functions to add unless the problem is in them. Describe behavior.
- No attribution lines.

## Tracking issues

When work splits into several PRs, one issue states the overall problem and outcome, and each PR says `Part of #N` until the last one, which says `Closes #N`. Only break the outcome into a list when the parts can land independently, and phrase each item as an outcome, not a task.

## Example

```
Settings: Caps Lock toggle does nothing under keyd, and keyd's remaps are invisible

Every install enables keyd with `system/etc/keyd/default.conf`, which remaps Caps Lock and Left Ctrl (tap Escape, hold Ctrl) and turns a held Tab into a system-wide vim layer. keyd acts below Hyprland, so Settings > Keyboard's "Caps Lock as Escape" toggle, an XKB option, has no effect in either position, and nothing in Settings mentions the keyd remaps at all.

The toggle must go, and the Keyboard section must show what keyd does, read from its config.
```
