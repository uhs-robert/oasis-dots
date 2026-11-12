---
name: time-estimates
description: Estimate how long a skilled human developer without AI needs for finished work (a PR, a commit range, a fix). Use when the owner asks for a time estimate, or a report skill asks for one.
---

# Time estimates

Estimate the work a skilled developer does, not the work the agents did.

## Measure first

1. Get the size of the change: `git show --stat` or `gh pr view <pr> --json additions,deletions,files`. Leave out generated files (minified output, lock files, data copies).
2. Note what the change copies from existing code (a picker, a loader, a pattern). Copying is faster than designing.

## The developer

- Knows this codebase, its tools and its deploy steps.
- Debugs the normal way: a debugger, browser devtools, logs, reading the code.
- Works without AI.

## Price the shortest realistic path

- Drop every agent detour: scouts that found nothing, extra debug passes, digs through build output, and fix rounds for mistakes a human does not make.
- A bug with a visible symptom: the developer finds the cause with the debugger or devtools. Price that at 10-30 minutes unless the symptom is hidden or intermittent.
- Do not pad a phase with a safety margin. Do not add a contingency line.

## Leave out, and say so in one line

Design discussions and owner decisions, waits for review or deploy, and meetings. These cost the same with or without AI.

## Check the total against the size

Pick a rate of 10-50 finished, tested lines per hour. Copied or simple code runs near 50. Intricate code runs near 10. Divide the line count by the rate to get the coding time.

Add the time for diagnosis and hand tests to the coding time. If the total is more than twice that sum, name the reason in the table or cut the estimate. This is a sanity check, not the price.

## Output

1. One line: the total in hours, in quarter-hour steps, with minutes: "3.5 hours (210 minutes)". Never convert to days, even past 8 hours: "32 hours (1920 minutes)".
2. One line: the size of the change and what it copied.
3. A table of phases with time in minutes and the main driver. List only the phases that apply. A phase can show a range ("60-90 min").
4. One line: what the estimate leaves out.

The total is one figure, not a range. Take the midpoint of each phase range, add them, and round to the nearest quarter hour.

## Worked example

A change copies an existing picker into a popup, about 200 lines.

3 hours (180 minutes)

About 200 lines. It copies the existing picker and the way another list loads its data.

| Phase | Time | What drives it |
|---|---|---|
| Read the popup and the existing picker | 20-30 min | Finding the input, the choices, and how the second view reuses the popup. |
| Data file, loader and build-script line | 15-20 min | Copying how the other list loads. |
| Dropdown behavior | 60-90 min | Keyboard handling: Enter must not take over custom text, and Escape must close the list before it cancels the editor. Touch picking and value updates take the rest. |
| Styling | 15-20 min | A short list inside the popup, in the existing style. |
| Hand test, both layouts | 30-40 min | Seven checks in two layouts. |
| PR | 10-15 min | |

The midpoints are 25, 17.5, 75, 17.5, 35 and 12.5 minutes. They sum to 182.5 minutes, which rounds to 3 hours.

Leaves out: the design discussion.
