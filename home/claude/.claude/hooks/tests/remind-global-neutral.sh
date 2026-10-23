#!/usr/bin/env bash
# Tests for remind-global-neutral.sh: it reminds for shared agent definition paths in the installed config directory
# (direct, through a symlink to a checkout, or with only some entries symlinked) and stays silent and successful for
# runtime state, other files, unrelated checkouts and malformed input.
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
# source/ is a checkout's copy of the config directory; home/.claude links to it. partial/ links only some entries.
mkdir -p "$tmp/source/skills/x" "$tmp/source/hooks" "$tmp/source/todos" "$tmp/home" "$tmp/partial" "$tmp/real_dir/skills" \
  "$tmp/elsewhere/skills/z" "$tmp/lookalike/home/claude/.claude/skills/y" "$tmp/project/.claude"
ln -s "$tmp/source" "$tmp/home/.claude"
ln -s "$tmp/elsewhere/skills" "$tmp/partial/skills"
touch "$tmp/source/CLAUDE.md" "$tmp/source/settings.json"

run() { HOME=$tmp/home bash "$hook" <<<"$1"; }
fires() { [[ $(run "$1") == *'"additionalContext"'*'unrelated repository'* ]]; }
silent() {
  local out
  out=$(run "$1") && [[ -z $out ]]
}
fires_in() { [[ $(CLAUDE_CONFIG_DIR=$1 bash "$hook" <<<"$2") == *'"additionalContext"'* ]]; }
edit() { printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$1"; }

check "fires for a skill through the config symlink" fires "$(edit "$tmp/home/.claude/skills/x/SKILL.md")"
check "fires for a new file there" fires "$(edit "$tmp/home/.claude/skills/new/SKILL.md")"
check "fires for the symlink's target path" fires "$(edit "$tmp/source/skills/x/SKILL.md")"
check "fires for settings" fires "$(edit "$tmp/home/.claude/settings.json")"
check "fires for the global CLAUDE.md" fires "$(edit "$tmp/home/.claude/CLAUDE.md")"
check "fires for a hook" fires "$(edit "$tmp/home/.claude/hooks/h.sh")"
check "fires for a command" fires "$(edit "$tmp/home/.claude/commands/c.md")"
check "fires for status.d" fires "$(edit "$tmp/home/.claude/status.d/s.sh")"
check "fires for Write" fires '{"tool_name":"Write","tool_input":{"file_path":"'"$tmp"'/home/.claude/commands/c.md"}}'
check "fires for NotebookEdit" fires '{"tool_name":"NotebookEdit","tool_input":{"notebook_path":"'"$tmp"'/home/.claude/skills/n.ipynb"}}'
check "fires for a real, unlinked config directory" fires_in "$tmp/real_dir" "$(edit "$tmp/real_dir/skills/s/SKILL.md")"
check "fires for an entry symlinked on its own" fires_in "$tmp/partial" "$(edit "$tmp/elsewhere/skills/z/SKILL.md")"
check "silent for runtime state through the symlink" silent "$(edit "$tmp/home/.claude/projects/p/memory/m.md")"
check "silent for runtime state at the symlink's target" silent "$(edit "$tmp/source/todos/t.json")"
check "silent for local settings" silent "$(edit "$tmp/home/.claude/settings.local.json")"
check "silent for a CLAUDE.md at a project root" silent "$(edit "$tmp/project/CLAUDE.md")"
check "silent for a CLAUDE.md in a project .claude" silent "$(edit "$tmp/project/.claude/CLAUDE.md")"
check "silent for a skill in an unrelated checkout" silent "$(edit "$tmp/lookalike/home/claude/.claude/skills/y/SKILL.md")"
check "silent for an ordinary file" silent "$(edit "$tmp/project/README.md")"
check "silent for a path missing from the input" silent '{"tool_name":"Edit","tool_input":{}}'
check "empty input succeeds silently" silent ''
check "malformed JSON succeeds silently" silent 'not json {'

exit $((failures > 0))
