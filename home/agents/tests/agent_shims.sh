#!/usr/bin/env bash
# Tests .local/bin/agent-shims against stub agents in a temporary folder: it writes a shim only for an agent on PATH,
# removes the shim of one that is gone, skips shims when it looks for agents, and --remove clears the folder.
set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
script=$here/../.local/bin/agent-shims
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

fail() {
  failures=$((failures + 1))
  echo "FAIL $*" >&2
}

mkdir "$work/agents" "$work/tools"
for tool in bash mkdir ln rm readlink rmdir; do
  ln -s "$(command -v "$tool")" "$work/tools/$tool"
done
printf '#!/bin/sh\n' >"$work/launcher"
chmod +x "$work/launcher"
stub() { printf '#!/bin/sh\n' >"$work/agents/$1" && chmod +x "$work/agents/$1"; }

export AGENT_SHIMS_DIR=$work/shims AGENT_RUN=$work/launcher
sync() { PATH="$work/shims:$work/agents:$work/tools" "$script" "$@" 2>&1; }
shims() { (cd "$work/shims" 2>/dev/null && printf '%s ' *); }

stub claude
stub codex
out=$(sync) || fail "first sync failed: $out"
[[ $(shims) == "claude codex " ]] || fail "first sync: shims '$(shims)', want claude codex"
[[ $work/shims/claude -ef $work/launcher ]] || fail "claude shim does not link to the launcher"
[[ $out == *"added claude"* ]] || fail "first sync: output '$out'"

# A second run with nothing changed says nothing.
out=$(sync)
[[ -z $out ]] || fail "idle sync printed '$out'"

# An agent installed later gets its shim, one uninstalled loses it.
stub opencode
rm "$work/agents/codex"
out=$(sync)
[[ $(shims) == "claude opencode " ]] || fail "after changes: shims '$(shims)', want claude opencode"
[[ $out == *"removed codex"* ]] || fail "after changes: output '$out'"

# The shim folder ahead on PATH never counts as an install, nor does a launcher link elsewhere on PATH.
rm "$work/agents/opencode"
ln -s "$work/launcher" "$work/agents/opencode"
sync >/dev/null
[[ ! -e $work/shims/opencode && ! -L $work/shims/opencode ]] || fail "a launcher link counted as an installed agent"

# A dead link left by the old stowed shims is replaced for an installed agent and removed for a missing one.
rm -f "$work/shims/claude"
ln -s "$work/gone/agent-run" "$work/shims/claude"
ln -s "$work/gone/agent-run" "$work/shims/qwen"
sync >/dev/null
[[ $work/shims/claude -ef $work/launcher ]] || fail "dead claude link not replaced"
[[ ! -L $work/shims/qwen ]] || fail "dead qwen link not removed"

out=$(sync --remove) || fail "--remove failed: $out"
[[ ! -e $work/shims ]] || fail "--remove left the folder: '$(shims)'"
sync --remove >/dev/null || fail "--remove with no folder failed"

if [[ $failures -gt 0 ]]; then
  echo "agent-shims: $failures failed" >&2
  exit 1
fi
echo "agent-shims: ok"
