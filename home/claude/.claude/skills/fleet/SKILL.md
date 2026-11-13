---
name: fleet
description: Plan and launch a fleet of full-auto orchestrator sessions for a repo's idea docs. Scouts size the pieces, the owner answers the logistics and design questions up front, the decisions go into the plan docs, and one tmux window per bundle runs an orchestrator. A silent watchdog wakes the planner only when a session stalls. Use when the owner asks to plan a fleet, an overnight run or parallel orchestrators; for one orchestrator, use ~/.claude/skills/orchestrator-handoff/spawn-orchestrator.sh instead.
argument-hint: "[project] [pieces to leave out]"
---

# Fleet

One session plans the work of many. It asks the owner every question once, writes the answers into the plan docs, then starts one full-auto orchestrator per bundle of pieces in tmux. After the launch the planner only watches.

Run this skill in an orchestrator session in focus mode, and load the `orchestrator` skill first. Focus mode keeps the planner from taking pieces itself. The planner delegates all reading and writing of code to agents and follows the orchestrator's briefing rules for every owner question.

Arguments: `$ARGUMENTS`

## What the fleet sessions do

- Each fleet session runs `/orchestrator auto` and claims its own docs with `plans claim --as <its ListAgents name>`. The planner leaves `owner_session` empty and never claims.
- Fleet sessions skip the interview and the plan approval, because the planner asked the design forks up front. They still run the overlap check.
- Merges go through the repo's own merge step only, and through no other merge command. Read the merge step from the repo's `AGENTS.md` or `CLAUDE.md`, and ask the owner if neither names one. The launch prompt carries the rule in `<merge_rule>`.
- Session names do not start with the repo directory name, because orchestrators already in that repo use such names. Use a short prefix of your own, then the bundle.
- Sessions coordinate by `SendMessage`, found through `ListAgents`. Nobody coordinates the fleet unless the owner chose a coordinator.

## Procedure

1. Pick the scope. Run `plans ls` and take the `idea` docs of the project. Drop the pieces the owner excludes and leave parked docs out.
2. Scout in parallel. Split the pieces into about 4 groups by area and start one read-only Sonnet agent per group. Each scout writes `<main checkout>/.logs/<project>/fleet-planning/<id>.md` per piece with these items:
   - what exists, with paths
   - a build plan with files, tests and docs
   - size (S, M or L) and the number of PRs
   - design forks, each with options and a recommendation
   - hand checks that the repo tools cannot reach
   - shared files, and dependencies on the other pieces, which the brief names

   Each scout reports one line per piece: size, PRs, forks, hand checks. A scout takes about 2 to 3 minutes and 80k to 100k tokens.
3. Ask the logistics questions while the scouts run. Use `AskUserQuestion`, and see "Questions" below.
4. Read the scout reports. Then pull only the fork sections, for example with `awk` over the scout files.
5. Surface the fleet-level risks and ask the owner about each one. See "Risk checklist".
6. Ask the design forks in rounds of four. Ask only the material ones: security, user-visible defaults and scope that blocks a piece. Record every other fork as "Assumed: the scout's recommendation".
7. Write the decisions into each doc with `plans note <id> --section Decisions`:
   - the owner's answers, marked `(owner)`
   - the assumed forks
   - the tier
   - the fleet merge rules above
   - the path of the scout file, which serves as the build plan

   Set the order with `plans set <id> 'depends_on=[...]'` and set `status=approved`. Leave `owner_session` empty. Run `plans lint`.
8. Bundle the pieces. Add up the cost per piece from the table below and fill each session to about 60 percent of the budget. Keep pieces that edit the same files in sequence in one bundle. Put the order between bundles in `depends_on` and in the roster.
9. Write the roster from `roster.md` in this directory to `<main checkout>/.logs/<project>/fleet-planning/ROSTER.md`. Name every outside session that works in the same repo, so the fleet expects its rebases.
10. Write one launch prompt per bundle from `launch-prompt.txt` to `<main checkout>/.logs/<project>/fleet-planning/prompts/<session>.txt`. A Haiku agent can fill both templates from your bundle table. Read the result before you launch.
11. Launch with `launch.sh`, or hand the prompts to the owner if the owner chose to start the sessions by hand.
12. Start the watchdog. See "Watchdog".

## Cost table

An estimate from one run (13 pieces in 7 sessions). Ask the owner to confirm the numbers, and change them here when a run shows better ones.

| Size | Orchestrator context per piece |
|---|---|
| L | 200k |
| M | 100k |
| S | 60k |

The target is 60 percent of the session budget. A 500k budget takes about 300k of work, so the session never needs a handoff. A fleet session never hands off: at the budget it winds down and stops.

## Questions

Ask the owner these every run, in one `AskUserQuestion` round while the scouts work:

- How the sessions start: the planner launches them in tmux, or the owner starts them by hand.
- What happens to finished work: merge to main through the repo's merge step, or stop at review-ready PRs. A merge needs a passing check and reviewer approval.
- The role of the planner: plan only, or also coordinate the sessions.
- The context budget per session, in tokens. The launch sets it in `CLAUDE_CONTEXT_BUDGET` and in the prompt.
- Hand checks: the default is to hold such a piece unmerged, as stock full auto does. The other choice is to merge it and append the hand checks to `<main checkout>/.logs/<project>/morning-checks.md` for the owner.
- Which pieces to leave out, and whether the fleet can release or bump a version.

## Risk checklist

Check each item against the scout reports and ask the owner about each one that applies:

- Hand checks. Count how many pieces have them and how that interacts with the hand-check choice above.
- Scheduled CI that publishes `main`. A merge overnight can reach a release build.
- Machine load. Several sessions each run builds, tests and nested sessions at once.
- Hot shared files and byte budgets. Name each one in the roster with its rule.
- An outside session in the same repo. The fleet rebases onto its merges.

## Watchdog

The watchdog is silent until a session needs the planner. `watch.sh` makes one check per run. It never types into a pane, claims a piece, merges or answers a permission prompt.

Start one background loop with the `Bash` tool and `run_in_background`, with this command (fill in the fleet session and the project):

```
sleep 1800; while true; do out=$(timeout 900 ~/.claude/skills/fleet/watch.sh <fleet-session> <project> 2>&1); rc=$?; if [ "$rc" -ne 0 ] || [ "$out" != ok ]; then echo "$out"; echo "watch.sh exit $rc"; exit 0; fi; sleep 1800; done
```

When the fleet's pieces span several plan projects, run the check as `FLEET_ALL_PROJECTS=1 ~/.claude/skills/fleet/watch.sh <fleet-session> <project>`. The check then finds each session's docs in every project, and `<project>` only names the log and state directory.

It sleeps first, so its first check does not compare against a manual run. It checks every 30 minutes and exits only on a result that is not `ok`. That exit wakes the planner, and a healthy night costs no tokens. A check that crashes or hangs past 15 minutes (`timeout 900`, exit 124) also exits the loop, with its output and exit status, so the loop never spins on or hangs behind a broken check.

A check prints `ok`, `all finished`, or one line per problem:

- `STUCK <name>`: the session runs claude, sits idle with an empty prompt box and owns a piece in `building` status with `waiting_on` empty. For 30 minutes it shows no activity: no pane change, commit, plan doc change, new `.logs` file or changed file in its branch worktree. Set the time with `FLEET_STUCK_SECONDS`.
- `PROMPT <name>`: the session waits on a permission prompt.
- `LOST <name>`: claude exited while the session still owns unfinished pieces, or before its first claim. Such a session never counts as finished.
- `EXITED <name>`: claude exited with nothing unfinished.
- `GONE <name>`: the session's tmux window is gone while it still owns unfinished pieces, or never claimed. It never counts as finished.
- `STOPPED <fleet>`: the fleet's tmux session is gone.

When the loop exits, read its output, then:

1. `all finished` or `STOPPED`: tell the owner and stop. Do not start the loop again.
2. Look at each named session with `tmux capture-pane -p -t <fleet-session>:<name>`.
3. A `STUCK` session that is really stuck gets a nudge by `SendMessage` to its `ListAgents` name: continue the building piece, or set `waiting_on` and say why it is held. Tell the owner about `PROMPT`, `LOST`, `EXITED` and `GONE`.
4. Start the loop again with the same command.

One stall wakes the planner once. The check keeps the stall in its state file, so the restarted loop stays quiet on it until the pane or the progress moves again. The state, kept per fleet, also carries the stall timing across runs. The log is `<main checkout>/.logs/<project>/fleet-watch.md`.

A session in another permission mode than the fleet sessions (`auto`) can have its `SendMessage` held for approval or lost. A test from an `auto` session reached an `auto` fleet session, but it could not cover a default-mode sender. So after a nudge, check the pane after a few minutes. If a `[Cross-session delivery notice]` says the message is held, or the session did not react, run `~/.claude/skills/fleet/watch.sh --nudge <fleet-session> <project> <name>`. It types the nudge text into that window only when the pane is idle with an empty prompt box and a claude process below it, and it logs the nudge.

## Placeholders

Fill these in `launch-prompt.txt` and `roster.md`:

| Placeholder | Meaning |
|---|---|
| `<session>` | the bundle's session name, also its tmux window name |
| `<session_count>` | how many sessions the fleet has |
| `<project>` | the plan project of the pieces |
| `<budget>` | the context budget in tokens |
| `<work_tokens>` | the work sized for the session, about 60 percent of the budget |
| `<pieces_in_order>` | the piece ids in build order, with a note where another session waits on one |
| `<main_checkout>` | the absolute path of the repo's main checkout |
| `<merge_step>` | the repo's merge command or skill, used inside `<merge_rule>`. Read it from the repo's `AGENTS.md` or `CLAUDE.md`. If neither names one, ask the owner |
| `<merge_rule>` | the owner's answer on finished work, in one or two sentences. To merge: "Merge only through the repo's merge step, `<merge_step>`, and through no other merge command. Run it once its check passes and the reviewer agent approves with no revisions." To stop at review-ready PRs: "Do not merge. Stop when each PR is review-ready." |
| `<hand_check_rule>` | the owner's hand-check choice, in one sentence |
| `<date>`, `<coordinator_line>` | the roster's date, and one sentence on whether a coordinator runs |
| `<release_rule>`, `<excluded_pieces_rule>` | the owner's release and exclusion rules, one sentence each |
| `<waiting_session>`, `<other_session>`, `<piece>`, `<file>`, `<outside_session>` | the roster's rows for order, shared files and outside sessions |

## Scripts

- `~/.claude/skills/fleet/launch.sh <fleet-session> <budget> <name>=<prompt-file>...` creates the tmux session with one window per bundle, each running `CLAUDE_CONTEXT_BUDGET=<budget> claude -n <name> --permission-mode auto "<prompt>"`. It refuses a session or window name that exists, kills a half-made session on failure and checks each pane for the prompt. It prints `tmux switch-client -t <fleet-session>`: tell the owner to run it, because the windows live in a separate tmux session.
- `~/.claude/skills/fleet/watch.sh <fleet-session> <project>` is one watchdog check. `watch.sh --nudge <fleet-session> <project> <name>` is the fallback nudge.
