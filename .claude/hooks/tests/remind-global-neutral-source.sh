#!/usr/bin/env bash
# Tests for remind-global-neutral-source.sh: the reminder fires for this repo's source of the global agent files in any
# checkout or worktree, and stays silent for runtime-style paths, project files and paths behind the installed symlink
# (the global hook covers those).
# shellcheck disable=SC2329 # run, fires and silent are called by name through check
set -u
hook=$(cd "$(dirname "$0")" && pwd)/../remind-global-neutral-source.sh
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
mkdir -p "$tmp/main/home/claude/.claude/skills/x" "$tmp/main/.claude/worktrees/w/home/claude/.claude/agents" "$tmp/home"
ln -s "$tmp/main/home/claude/.claude" "$tmp/home/.claude"

run() { HOME=$tmp/home bash "$hook" <<<"$1"; }
fires() { [[ $(run "$1") == *'"additionalContext"'*'unrelated repository'* ]]; }
silent() {
  local out
  out=$(run "$1") && [[ -z $out ]]
}
edit() { printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$1"; }

check "fires for a skill in another worktree" fires "$(edit "$tmp/main/.claude/worktrees/w/home/claude/.claude/skills/x/SKILL.md")"
check "fires for an agent in a worktree" fires "$(edit "$tmp/main/.claude/worktrees/w/home/claude/.claude/agents/a.md")"
check "fires for the global CLAUDE.md in a worktree" fires "$(edit "$tmp/main/.claude/worktrees/w/home/claude/.claude/CLAUDE.md")"
check "fires for NotebookEdit" fires '{"tool_name":"NotebookEdit","tool_input":{"notebook_path":"'"$tmp"'/main/.claude/worktrees/w/home/claude/.claude/skills/n.ipynb"}}'
check "silent for runtime state in a worktree" silent "$(edit "$tmp/main/.claude/worktrees/w/home/claude/.claude/todos/t.json")"
check "silent for local settings" silent "$(edit "$tmp/main/.claude/worktrees/w/home/claude/.claude/settings.local.json")"
check "silent for a project skill" silent "$(edit "$tmp/main/.claude/skills/y/SKILL.md")"
check "silent for an ordinary file" silent "$(edit "$tmp/main/README.md")"
check "silent behind the installed symlink" silent "$(edit "$tmp/home/.claude/skills/x/SKILL.md")"
check "silent behind the symlink's target" silent "$(edit "$tmp/main/home/claude/.claude/skills/x/SKILL.md")"
check "silent for a path missing from the input" silent '{"tool_name":"Edit","tool_input":{}}'
check "empty input succeeds silently" silent ''
check "malformed JSON succeeds silently" silent 'not json {'

exit $((failures > 0))
