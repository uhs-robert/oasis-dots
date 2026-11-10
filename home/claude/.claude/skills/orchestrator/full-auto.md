# Full auto

Read when the mode file holds `auto`, before acting.

Full auto is the `auto` word in the mode file. It turns on when the owner says "full auto" or passes `auto` to this skill, and off when the owner says to stop full auto. It overrides `queue`: with both words set, the queue rules stay off. It works only on assigned pieces: those this session owns and those handed over by `BATON`. When every assigned piece is merged or held, give the "Status report" per the `orchestrator-status` skill and stop. Under Judgment calls, list the `auto:` calls of merged pieces from the session log as well as those in the Decisions of live docs.

In full auto you act on your own recommendation at each owner gate instead of asking: the interview questions, plan approval, the tier, forks while building and merge approval. Owner briefs, `AskUserQuestion` and the "Briefing the owner" rules do not apply to them. For each one, run `plans note <id> --section Decisions "auto: chose X over Y because Z; revisit if W"`. The `auto:` lines go only in the plan doc's Decisions. At merge, the piece's line in the session log (`<main checkout>/.logs/session-<session>.md`) carries them, as `orchestrator-status` defines. Workers still report forks to you, and only you decide them. A held piece's `waiting_on="owner: ..."` is never answered or cleared by you: only the owner clears it, so a later turn or a session after `/clear` never treats a held test as passed. Never pick the trivial tier and never re-tier down.

- Merge: run `ship-batch` only when `merge-prs.sh --check` passes and the reviewer agent approves with no revisions. Never pass `--skip-review-gate` on your own judgment. If a review wait cannot finish, hold the piece.
- Fix rounds: past 2, use your own judgment and log each extra round as a judgment call.
- Screenshots that need a decision: a reviewer agent judges, and you log its verdict as a judgment call. A look choice only the owner can make holds the piece.
- Context budget: never hand off. At the budget hook, wind down: finish to a break, give the status report and stop. This wins over the hook's handoff offer.
- Held: a hands-on test, a classifier denial, a look choice, a skipped review wait and anything else left for the owner. Hold the piece unmerged in review, run `plans set <id> waiting_on="owner: <what>"` and list it under Outstanding. Do not ask. For a classifier denial, hand over the `!` command and go on with other work.
- Never in full auto: an irreversible action (`cancel`, `plans claim --force`) or a handoff. List it under Outstanding.
