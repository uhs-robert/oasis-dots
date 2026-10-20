#!/usr/bin/env bash
# Tests for context-budget.sh: an orchestrator session gets the size-check note once, then the handoff note once;
# other sessions, agents and a sidechain's usage are ignored.
set -u
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
  usage_line 100000
} >"$t"
check "below the threshold says nothing" test -z "$(run_hook "$t" s1)"

usage_line 145000 >>"$t"
out=$(run_hook "$t" s1)
check "at 140k the orchestrator gets the size check" grep -q 'Size check' <<<"$out"
check "the size check bounds a piece by the handoff threshold" grep -q 'stays under 175k' <<<"$out"
check "the size check carries the cost table" grep -q '30-45k' <<<"$out"
check "the note is PostToolUse context" test "$(jq -r .hookSpecificOutput.hookEventName <<<"$out")" = PostToolUse
check "the wind-down note comes once" test -z "$(run_hook "$t" s1)"

usage_line 300000 true >>"$t"
check "a sidechain's usage is not the session's" test -z "$(run_hook "$t" s1)"

usage_line 165000 >>"$t"
usage_line 170000 >>"$t"
check "at 170k there is no handoff note yet" test -z "$(run_hook "$t" s1)"

usage_line 176000 >>"$t"
out=$(run_hook "$t" s1)
check "at 175k the orchestrator is told to hand off" grep -q 'Hand off now' <<<"$out"
check "the handoff note carries the spawn step" grep -q 'spawn-successor.sh' <<<"$out"
check "the handoff note says not to reload the skill" grep -q 'do not load it again' <<<"$out"
check "the handoff note comes once" test -z "$(run_hook "$t" s1)"

h="$tmp/handoff.jsonl"
{
  printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"%s/.claude/skills/orchestrator/SKILL.md"}}]}}\n' "$HOME"
  usage_line 180000
} >"$h"
check "a successor that read the skill file counts as an orchestrator" grep -q 'Hand off now' <<<"$(run_hook "$h" s2)"

o="$tmp/other.jsonl"
{
  printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"grep \\"text\\":\\"Base directory for this skill: %s/.claude/skills/orchestrator\\\\n"}}]}}\n' "$HOME"
  usage_line 170000
} >"$o"
check "a session that only mentions the skill is left alone" test -z "$(run_hook "$o" s3)"
check "an agent inside an orchestrator is left alone" test -z "$(run_hook "$h" s4 '+ {agent_id: "a1"}')"
check "an orchestrator outside tmux is left alone" test -z "$(test_tmux='' run_hook "$h" s5)"

((failures == 0)) && echo "all passed" || exit 1
