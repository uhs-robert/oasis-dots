---
name: interview
description: Interview the owner until 90% confident a build can be done correctly, then present the plan for approval. Use for build requests whose requirements are not fully pinned down; skip small or fully specified tasks (typo fixes, lookups, exact instructions).
argument-hint: "[task]"
---

# Interview

Task: `$ARGUMENTS`, or the conversation's request when that is empty.

Interview me until you are 90% confident you can build this correctly, then present the plan and wait for my approval.

1. Investigate first: the code, the issue, the repo docs. Never ask what they already answer.
2. Interview in rounds with `AskUserQuestion`, up to 4 questions per round, by topic. Before each round, brief me in one block: conclusion first, then per option what happens, pros, cons and cost, the tradeoff, and your recommendation, with that option first.
3. Ask only what changes the build: scope, acceptance criteria, constraints, interfaces, tradeoffs. A minor choice with one sensible answer is not asked; state it as "Assumed: X".
4. After each round, state your confidence in percent and the unknowns that keep it below 90%. Keep them as `- [ ]` items under the plan doc's Open questions, and move each answer into Decisions, dated. If the piece has no doc, make one with `plans new <project> <id> --kind <kind> --after <id>` (or `--before <id>`), then `plans claim <id> --as <session from ListAgents>`. If `.gitignore` lacks `/.plans/` and `/.logs/`, first add both to `<git-common-dir>/info/exclude`. Outside a git repo, keep the plan in chat.
5. At 90% or more, write the plan into that doc, run `plans set <id> status=planned`, present it with the assumptions near the top, and ask for approval with `AskUserQuestion`. Build only after I approve, then run `plans set <id> status=approved`.
6. If a later finding drops confidence below 90%, resume interviewing.
