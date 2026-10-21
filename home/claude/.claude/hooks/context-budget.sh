#!/usr/bin/env bash
# PostToolUse: tell an orchestrator session when its context nears the owner's 200k budget, so it winds down and hands
# off before quality drops. The model has a 1M window, so nothing stops it at 200k; this note is the only signal.
# Two notes, each sent once per session: at CLAUDE_CONTEXT_WIND_DOWN tokens (size check: only small pieces from
# here), and at CLAUDE_CONTEXT_HANDOFF (hand off now). The handoff threshold leaves ~25k for the handoff itself,
# which keeps forwarding its agents' reports until the last piece moves. The handoff note carries the steps so the
# session need not load the orchestrator-handoff skill just to start; the sizes in the first note are rough
# measurements of orchestrator context per kind of piece.
# Other sessions and agents are left alone: only a session that loaded the orchestrator skill gets the notes.
# Outside tmux there is nowhere to open the successor, so the session gets no notes and its context keeps growing.
set -u
input=$(cat)
[[ -n ${TMUX:-} ]] || exit 0
[[ -z $(jq -r '.agent_id // empty' <<<"$input") ]] || exit 0
transcript=$(jq -r '.transcript_path // empty' <<<"$input")
session=$(jq -r '.session_id // empty' <<<"$input")
[[ -f $transcript && $session =~ ^[A-Za-z0-9-]+$ ]] || exit 0

wind_down=${CLAUDE_CONTEXT_WIND_DOWN:-140000}
handoff=${CLAUDE_CONTEXT_HANDOFF:-175000}
state_dir=${CLAUDE_CONTEXT_STATE_DIR:-${XDG_RUNTIME_DIR:-/tmp}/claude-context-budget}
mkdir -p "$state_dir"
state="$state_dir/$session"
stage=$(cat "$state" 2>/dev/null || echo unknown)

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
  note="Context budget: $((used / 1000))k of the owner's 200k. Hand off now. If the orchestrator-handoff skill is already in context, do not load it again. Steps: (1) tell the owner in one line that you hand off at the context budget; (2) run ~/.claude/skills/orchestrator-handoff/spawn-successor.sh <your session name>; (3) end the turn; (4) on READY, follow the skill's Hand over from step 1."
  echo 2 >"$state"
elif ((used >= wind_down && stage < 1)); then
  note="Context budget: $((used / 1000))k of the owner's 200k. Size check: from here start only small pieces, under ~10k of orchestrator context, and only if current + its estimate stays under $((handoff / 1000))k (a fix round, a doc update, owner-test prep, answering a question, a gate or merge of a ready PR); start no new PR cycle. With no small piece left, ask the owner (AskUserQuestion) which open item to do next and offer to hand it to a fresh session; never end a turn idle. Costs: full PR cycle (brief, review, fix round, suites, PR, gate, merge) 30-45k; fix round, owner-test prep or a question 3-8k; the handoff itself ~20k. At $((handoff / 1000))k you will be told to hand off."
  echo 1 >"$state"
fi
[[ -n $note ]] || exit 0
jq -n --arg n "$note" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $n}}'
