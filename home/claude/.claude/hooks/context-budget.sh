#!/usr/bin/env bash
# PostToolUse: tell an orchestrator session when its context nears the owner's budget (CLAUDE_CONTEXT_BUDGET, 300k),
# so it winds down and hands off before quality drops. The model has a 1M window, so nothing stops it at the budget;
# this note is the only signal.
# Two notes, each sent once per session: at the wind-down point (size check: only small pieces from here), and at the
# handoff point (hand off now). Both sit a fixed distance below the budget, not a fraction of it, because the work
# they make room for has a fixed size: the handoff point leaves 25k for the handoff itself (~20k), which keeps
# forwarding its agents' reports until the last piece moves, and the wind-down point 40k more, so one in-flight PR
# cycle (30-45k) can finish. CLAUDE_CONTEXT_WIND_DOWN and CLAUDE_CONTEXT_HANDOFF override either point. The handoff note carries the steps so the
# session need not load the orchestrator-handoff skill just to start; the sizes in the first note are rough
# measurements of orchestrator context per kind of piece.
# The owner can state a different budget in chat: the orchestrator writes the number to <state dir>/<session id>.budget,
# which wins over CLAUDE_CONTEXT_BUDGET because the env var cannot change mid-session. Its session id is
# $CLAUDE_CODE_SESSION_ID in the Bash tool, the same id the hook gets as session_id.
# Other sessions and agents are left alone: only a session that loaded the orchestrator skill gets the notes.
# Outside tmux there is nowhere to open the successor, so the session gets no notes and its context keeps growing.
set -u
input=$(cat)
[[ -n ${TMUX:-} ]] || exit 0
[[ -z $(jq -r '.agent_id // empty' <<<"$input") ]] || exit 0
transcript=$(jq -r '.transcript_path // empty' <<<"$input")
session=$(jq -r '.session_id // empty' <<<"$input")
[[ -f $transcript && $session =~ ^[A-Za-z0-9-]+$ ]] || exit 0

state_dir=${CLAUDE_CONTEXT_STATE_DIR:-${XDG_RUNTIME_DIR:-/tmp}/claude-context-budget}
mkdir -p "$state_dir"
budget=${CLAUDE_CONTEXT_BUDGET:-300000}
budget_file="$state_dir/$session.budget"
if [[ -f $budget_file ]]; then
  file_budget=$(<"$budget_file")
  [[ $file_budget =~ ^[0-9]+$ ]] && budget=$((10#$file_budget))
fi
handoff=${CLAUDE_CONTEXT_HANDOFF:-$((budget - 25000))}
wind_down=${CLAUDE_CONTEXT_WIND_DOWN:-$((handoff - 40000))}
state="$state_dir/$session"
stage=$(cat "$state" 2>/dev/null || echo unknown)
# A budget file newer than the stage means the owner changed the budget since the stage was set, so the notes are due again.
if [[ $stage != unknown && $budget_file -nt $state ]]; then
  stage=0
  echo 0 >"$state"
fi

if [[ $stage == unknown ]]; then
  # The skill arrives either through /orchestrator (a text block starting with this line) or, on a handoff, through
  # a Read of its file. Both patterns include their JSON key, so a command that merely mentions them (its quotes
  # escaped inside a string) does not match. A grep of the whole transcript is cheap next to a tool call, and runs
  # only until the session is recognised.
  skill_dir="$HOME/.claude/skills/orchestrator"
  grep -q -F -e "\"text\":\"Base directory for this skill: $skill_dir\\n" -e "\"file_path\":\"$skill_dir/SKILL.md\"" "$transcript" || exit 0
  stage=0
  echo 0 >"$state"
fi
((stage >= 2)) && exit 0

# The latest main-chain response's usage is the context it was sent with.
used=$(tac "$transcript" | grep -F '"usage"' | grep -v -F '"isSidechain":true' -m1 |
  jq '.message.usage | .input_tokens + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0)' 2>/dev/null)
[[ $used =~ ^[0-9]+$ ]] || exit 0

note=''
if ((used >= handoff)); then
  note="Context budget: $((used / 1000))k of $((budget / 1000))k. Hand off now, via ~/.claude/skills/orchestrator-handoff/spawn-successor.sh <your session name>; tell the owner in one line first, end the turn, and on READY follow the skill's Hand over from step 1."
  echo 2 >"$state"
elif ((used >= wind_down && stage < 1)); then
  note="Context budget: $((used / 1000))k of $((budget / 1000))k. Start only pieces under ~10k of orchestrator context that keep you under $((handoff / 1000))k, and no new PR cycle (30-45k; a fix round, owner-test prep or a question is 3-8k; the handoff ~20k). With none left, ask the owner (AskUserQuestion) which open item to do next and offer to hand it to a fresh session; never end a turn idle. At $((handoff / 1000))k you will be told to hand off."
  echo 1 >"$state"
fi
[[ -n $note ]] || exit 0
jq -n --arg n "$note" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $n}}'
