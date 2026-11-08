# Worker rules

For agents an orchestrator starts: implementers, fixers, reviewers and explorers. The brief names this file, the repo's `AGENTS.md` and the plan doc. Global `CLAUDE.md`, `AGENTS.md` and `settings.json` rules apply as well and are not repeated here. Where this file and the global `AskUserQuestion` rule differ, this file wins for workers.

## All workers

- Report in the last message: lead with the result, stay under 2,000 characters. Put anything longer (logs, full finding lists) in a file under `<main checkout>/.logs/<project>/<id>/` (from the plan doc path; create the directory if missing) and give its absolute path in the report. The report covers the changes, validation, deviations from the plan with the reason, and remaining concerns.
- Stop and report a fork instead of choosing, and do not ask the owner. A fork is a design choice the plan does not settle, a new mechanism or file, or scope growth.
- Leave nothing running when you report.
- Exploration stops after 20 minutes unless the brief sets another limit. Then report.
- Screenshots: read every one. Report one line per shot, either that it looks right or the problem. When the owner must decide on a shot, give its absolute path.

## Implementers and fixers

- Run targeted tests while building, each under 10 minutes. Run the full check once before reporting, only in a repo whose merge step does not run it. Run broader checks only when shared machinery changes.
- Commit, push the branch and report in the same turn. Open no PR. Do not amend a commit after pushing it.
- Before committing, finish with the `hierarchical-documentation` pass on your diff.
- With parallel agents, edit only the files the brief gives you and respect its "Do NOT" line. Use the shared code the brief names instead of reimplementing it. Put standalone work in a new file. Where you must share a file (a list, table, index or config), keep your edit a small addition.
- Concurrency or lifecycle work (signals, locks, processes that hand over or race): write tests that drive each risky path before you report.
- A fixer makes the smallest change that fixes the finding.
- A fix adds a test when, and only when, the bug could come back silently and nothing else would catch it. Show the test failing on the unfixed code first. Otherwise say in one line why there is no test.

## Reviewers

- Read only. Edit, commit, push and comment on nothing.
- Write the full findings to the file under `.logs/<project>/<id>/`, ranked by severity. Each finding has file:line, a concrete failure scenario, confidence (confirmed or plausible) and a suggested fix.
- Report the verdict plus one line per finding: severity, file:line, the failure in a sentence, whether it hits the stated requirement or the owner's real setup, and whether a fix is proportionate to the tier. Stay under 1,500 characters for a first review and under 800 for a follow-up review (the brief says which). Edge cases outside the requirement are notes in the file, not findings.
- Also check that the commit messages follow `commit-messages`, and ask whether the patch works around a design that is the real problem.
