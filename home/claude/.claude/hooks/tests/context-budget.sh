#!/usr/bin/env bash
# Tests for context-budget.sh: an orchestrator session gets the size-check note once, then the handoff note once;
# other sessions, agents and a sidechain's usage are ignored.
set -u
# The checks assume the default budget, so overrides from the caller's shell must not reach the hook.
unset CLAUDE_CONTEXT_BUDGET CLAUDE_CONTEXT_WIND_DOWN CLAUDE_CONTEXT_HANDOFF
hook="$(dirname "$0")/../context-budget.sh"
failures=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

check() {
  local name=$1
  shift
  if "$@"; then echo "ok   $name"; else
    echo "FAIL $name"
    failures=$((failures + 1))
  fi
}

skill_line() {
  printf '{"type":"user","message":{"content":[{"type":"text","text":"Base directory for this skill: %s/.claude/skills/orchestrator\\n\\n# Orchestrator"}]}}\n' "$HOME"
}
usage_line() { # $1 tokens, $2 isSidechain
  printf '{"type":"assistant","isSidechain":%s,"message":{"usage":{"input_tokens":2,"cache_read_input_tokens":%d,"cache_creation_input_tokens":0}}}\n' "${2:-false}" "$1"
}
run_hook() { # $1 transcript, $2 session id, $3 extra input fields
  jq -nc --arg t "$1" --arg s "$2" "{transcript_path: \$t, session_id: \$s} ${3:-}" |
    TMUX=${test_tmux-/tmp/tmux-test/default,1,0} CLAUDE_CONTEXT_STATE_DIR="$tmp/state" bash "$hook"
}

t="$tmp/orch.jsonl"
{
  skill_line
  usage_line 200000
} >"$t"
check "below the threshold says nothing" test -z "$(run_hook "$t" s1)"

usage_line 240000 >>"$t"
out=$(run_hook "$t" s1)
check "at 235k the orchestrator gets the size check" grep -q 'Start only pieces' <<<"$out"
check "the size check bounds a piece by the handoff threshold" grep -q 'under 275k' <<<"$out"
check "the size check says to ask the owner for the next task" grep -q 'never end a turn idle' <<<"$out"
check "the note names the 300k budget" grep -q 'of 300k' <<<"$out"
check "the size check carries the cost table" grep -q '30-45k' <<<"$out"
check "the note is PostToolUse context" test "$(jq -r .hookSpecificOutput.hookEventName <<<"$out")" = PostToolUse
check "the wind-down note comes once" test -z "$(run_hook "$t" s1)"

usage_line 400000 true >>"$t"
check "a sidechain's usage is not the session's" test -z "$(run_hook "$t" s1)"

usage_line 265000 >>"$t"
usage_line 270000 >>"$t"
check "at 270k there is no handoff note yet" test -z "$(run_hook "$t" s1)"

usage_line 276000 >>"$t"
out=$(run_hook "$t" s1)
check "at 275k the orchestrator is told to hand off" grep -q 'Hand off now' <<<"$out"
check "the handoff note carries the spawn step" grep -q 'spawn-successor.sh' <<<"$out"
check "the handoff note comes once" test -z "$(run_hook "$t" s1)"

h="$tmp/handoff.jsonl"
{
  printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"%s/.claude/skills/orchestrator/SKILL.md"}}]}}\n' "$HOME"
  usage_line 280000
} >"$h"
check "a successor that read the skill file counts as an orchestrator" grep -q 'Hand off now' <<<"$(run_hook "$h" s2)"

o="$tmp/other.jsonl"
{
  printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"grep \\"text\\":\\"Base directory for this skill: %s/.claude/skills/orchestrator\\\\n"}}]}}\n' "$HOME"
  usage_line 280000
} >"$o"
check "a session that only mentions the skill is left alone" test -z "$(run_hook "$o" s3)"
check "an agent inside an orchestrator is left alone" test -z "$(run_hook "$h" s4 '+ {agent_id: "a1"}')"
check "an orchestrator outside tmux is left alone" test -z "$(test_tmux='' run_hook "$h" s5)"

b="$tmp/budget.jsonl"
{
  skill_line
  usage_line 140000
} >"$b"
out=$(CLAUDE_CONTEXT_BUDGET=200000 run_hook "$b" s6)
check "a smaller budget moves the wind-down point to 40k before its handoff" grep -q 'under 175k' <<<"$out"
check "a smaller budget is the one the note names" grep -q 'of 200k' <<<"$out"
{
  skill_line
  usage_line 134000
} >"$b.low"
check "a smaller budget says nothing below its wind-down point" test -z "$(CLAUDE_CONTEXT_BUDGET=200000 run_hook "$b.low" s7)"

# The per-session budget file wins over the env var, and raising it re-arms the notes.
f="$tmp/file.jsonl"
{
  skill_line
  usage_line 276000
} >"$f"
echo 400000 >"$tmp/state/s8.budget"
check "a budget file beats the env var" test -z "$(CLAUDE_CONTEXT_BUDGET=300000 run_hook "$f" s8)"
echo 300000 >"$tmp/state/s9.budget"
check "a budget file sets the point the note names" grep -q 'of 300k' <<<"$(CLAUDE_CONTEXT_BUDGET=900000 run_hook "$f" s9)"
check "the handoff note had come once" test -z "$(run_hook "$f" s9)"
sleep 1
echo 350000 >"$tmp/state/s9.budget"
usage_line 330000 >>"$f"
check "a raised budget re-arms the notes" grep -q 'of 350k' <<<"$(run_hook "$f" s9)"
echo junk >"$tmp/state/s10.budget"
check "a malformed budget file falls back to the env var" grep -q 'of 200k' <<<"$(CLAUDE_CONTEXT_BUDGET=200000 run_hook "$b" s10)"
echo 080000 >"$tmp/state/s11.budget"
check "a budget file with a leading zero is read as decimal" grep -q 'of 80k' <<<"$(run_hook "$f" s11)"

((failures == 0)) && echo "all passed" || exit 1
