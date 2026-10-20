#!/usr/bin/env bash
# PostToolUse: tell an orchestrator session when its context nears the owner's 200k budget, so it winds down and hands
# off before quality drops. The model has a 1M window, so nothing stops it at 200k; this note is the only signal.
# Two notes, each sent once per session: at CLAUDE_CONTEXT_WIND_DOWN tokens (start no new piece), and at
# CLAUDE_CONTEXT_HANDOFF (hand off at the next break). They come early on purpose: the outgoing orchestrator keeps
# forwarding its agents' reports until the last piece moves, which costs context after the second note.
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
handoff=${CLAUDE_CONTEXT_HANDOFF:-160000}
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
  note="Context budget: this orchestrator session is at $((used / 1000))k of the owner's 200k budget. Hand off now: load the orchestrator-handoff skill and follow its \"Automatic handoff\" section, starting at the next natural break."
  echo 2 >"$state"
elif ((used >= wind_down && stage < 1)); then
  note="Context budget: this orchestrator session is at $((used / 1000))k of the owner's 200k budget. Start no new piece; finish what is in flight. At $((handoff / 1000))k you will be told to hand off."
  echo 1 >"$state"
fi
[[ -n $note ]] || exit 0
jq -n --arg n "$note" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $n}}'
