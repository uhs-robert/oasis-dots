---
name: orchestrator-status
description: Give the owner a session status report: what is done, what is outstanding, judgment calls to revisit and recommendations. Use when the owner asks for a status, a session summary or a wind-down report. The orchestrator also gives it at every handoff and at the end of full auto.
---

# Orchestrator status

One format for every report to the owner. The orchestrator gives it at every handoff (after the doc update), at wind-down (end of day), at the end of full auto and when the owner asks. Four parts, one short line per item:

- **Done:** what shipped this session. Read it from the session log `<main checkout>/.logs/session-<session>.md`, because `plans close` deletes a merged doc and its `.logs` folder. Before a merged doc is deleted, append one line to the log: id, PR, what shipped, and its judgment calls and settled forks from Decisions and Open questions. A successor adds the logs its predecessors name in their batons.
- **Outstanding:** `plans ls --owner <your session>`, `plans waiting` and `gh pr list`. Say what each waits on.
- **Judgment calls and forks to revisit:** choices you made for the owner and forks you settled, each with its reason, so the owner can overrule it. Read them from the Decisions and Open questions of your docs and from the session log lines.
- **Recommendations:** what to do next, from those sections and `plans next --all`.
