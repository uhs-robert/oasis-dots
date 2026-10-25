---
id: example
title: Example
status: draft
# approved: 2026-01-01   # a date; required once status is approved, implemented or deprecated
prs: []                  # PRs that approved or changed it
implements: []           # code paths; their READMEs link back
depends_on: []           # other spec ids
actions: []              # registry ids
keys: []                 # written mod+z
---
# Example

<!-- Copy to specs/core/<id>.md, set id to the file name (letters only), and delete the comments. -->

## What it is for
Who uses it, from where, to do what.

## Requirements
<!-- One per line: the id is the spec id in capitals, a dash and two digits. Ids are never reused. State what the user
sees or can do in plain words, never a tool. A known gap carries [gap: untested] or [gap: unmet] after the id.
A test proves a requirement by carrying `req: <ID>` in a comment or a vectors.tsv note. After editing run
python3 -B lib/check/steps/specs.py --write to regenerate specs/gaps.md. -->
- **EXAMPLE-01** One testable statement of behaviour, in plain words.
- **EXAMPLE-02** [gap: untested] A known gap is marked inline.

## Look
Described in words where it matters; optional screenshot.

## Not covered
Experimental or deliberately open parts.
