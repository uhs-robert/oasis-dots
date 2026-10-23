#!/usr/bin/env bash
# Tests for remind-global-neutral.sh: it reminds for global agent file paths (direct, via the ~/.claude symlink, and in
# any checkout) and stays silent and successful for project files and malformed input.
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

check "fires for a skill in a checkout's home/claude/.claude" fires "$(edit "$tmp/checkout/home/claude/.claude/skills/x/SKILL.md")"
check "fires for a new file there" fires "$(edit "$tmp/checkout/home/claude/.claude/skills/new/SKILL.md")"
check "fires for a settings file there" fires "$(edit "$tmp/checkout/home/claude/.claude/settings.json")"
check "fires through the ~/.claude symlink" fires "$(edit "$tmp/home/.claude/skills/x/SKILL.md")"
check "fires for a hook through the symlink" fires "$(edit "$tmp/home/.claude/hooks/h.sh")"
check "fires for a worktree checkout" fires "$(edit "$tmp/checkout/.claude/worktrees/w/home/claude/.claude/agents/a.md")"
check "fires for Write" fires '{"tool_name":"Write","tool_input":{"file_path":"'"$tmp"'/home/.claude/commands/c.md"}}'
check "fires for NotebookEdit" fires '{"tool_name":"NotebookEdit","tool_input":{"notebook_path":"'"$tmp"'/home/.claude/skills/n.ipynb"}}'
check "silent for a project skill" silent "$(edit "$tmp/checkout/.claude/skills/y/SKILL.md")"
check "silent for an ordinary file" silent "$(edit "$tmp/checkout/README.md")"
check "silent for a path missing from the input" silent '{"tool_name":"Edit","tool_input":{}}'
check "empty input succeeds silently" silent ''
check "malformed JSON succeeds silently" silent 'not json {'

exit $((failures > 0))
