#!/usr/bin/env bash
# Tests for remind-global-neutral.sh: it reminds for shared agent definition paths (direct and through the config
# directory's symlink) and stays silent and successful for runtime state, other files and malformed input.
# shellcheck disable=SC2329 # run, fires and silent are called by name through check
set -u
hook="$(dirname "$0")/../remind-global-neutral.sh"
failures=0

check() {
  local name=$1
  shift
  if "$@"; then echo "ok   $name"; else
    echo "FAIL $name"
    failures=$((failures + 1))
  fi
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/checkout/home/claude/.claude/skills/x" "$tmp/checkout/.claude/skills/y" "$tmp/home"
ln -s "$tmp/checkout/home/claude/.claude" "$tmp/home/.claude"

run() { HOME=$tmp/home bash "$hook" <<<"$1"; }
fires() { [[ $(run "$1") == *'"additionalContext"'*'unrelated repository'* ]]; }
silent() {
  local out
  out=$(run "$1") && [[ -z $out ]]
}
edit() { printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$1"; }

check "fires for a skill under the source tree" fires "$(edit "$tmp/checkout/home/claude/.claude/skills/x/SKILL.md")"
check "fires for a new file there" fires "$(edit "$tmp/checkout/home/claude/.claude/skills/new/SKILL.md")"
check "fires for settings there" fires "$(edit "$tmp/checkout/home/claude/.claude/settings.json")"
check "fires through the config symlink" fires "$(edit "$tmp/home/.claude/skills/x/SKILL.md")"
check "fires for a hook through the symlink" fires "$(edit "$tmp/home/.claude/hooks/h.sh")"
check "fires for a nested checkout" fires "$(edit "$tmp/checkout/.claude/worktrees/w/home/claude/.claude/agents/a.md")"
check "fires for Write" fires '{"tool_name":"Write","tool_input":{"file_path":"'"$tmp"'/home/.claude/commands/c.md"}}'
check "fires for NotebookEdit" fires '{"tool_name":"NotebookEdit","tool_input":{"notebook_path":"'"$tmp"'/home/.claude/skills/n.ipynb"}}'
check "fires for the global CLAUDE.md" fires "$(edit "$tmp/home/.claude/CLAUDE.md")"
check "silent for local settings" silent "$(edit "$tmp/home/.claude/settings.local.json")"
check "silent for a CLAUDE.md at a project root" silent "$(edit "$tmp/checkout/CLAUDE.md")"
check "silent for a CLAUDE.md in a project .claude" silent "$(edit "$tmp/project/.claude/CLAUDE.md")"
check "silent for runtime state through the symlink" silent "$(edit "$tmp/home/.claude/projects/p/memory/m.md")"
check "silent for runtime state in the source tree" silent "$(edit "$tmp/checkout/home/claude/.claude/todos/t.json")"
check "silent for a skill outside the shared tree" silent "$(edit "$tmp/checkout/.claude/skills/y/SKILL.md")"
check "silent for an ordinary file" silent "$(edit "$tmp/checkout/README.md")"
check "silent for a path missing from the input" silent '{"tool_name":"Edit","tool_input":{}}'
check "empty input succeeds silently" silent ''
check "malformed JSON succeeds silently" silent 'not json {'

exit $((failures > 0))
