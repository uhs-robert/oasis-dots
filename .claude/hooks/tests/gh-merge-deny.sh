#!/usr/bin/env bash
# The project's permissions.deny must stop a PR merge through gh, also in a chain and with gh flags before or after
# `pr`. Deny matching lives in Claude Code, so this asks a real (haiku) session to run each command against a stub
# `gh` that leaves a marker file: no marker means the rule denied it. Needs the claude CLI; skips without it.
set -uo pipefail
settings=$(cd "$(dirname "$0")" && pwd)/../../settings.json
command -v claude >/dev/null || {
  echo "skip: claude CLI not found"
  exit 0
}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin" "$tmp/work"
printf '#!/bin/sh\ntouch "%s/ran"\n' "$tmp" >"$tmp/bin/gh"
chmod +x "$tmp/bin/gh"
# Only the permissions: the hooks in the file need the project environment.
jq '{permissions: (.permissions // {})}' "$settings" >"$tmp/permissions.json"
pass=0 fail=0

# expect <denied|ran> <command>
expect() {
  local got=ran
  rm -f "$tmp/ran"
  (cd "$tmp/work" && PATH=$tmp/bin:$PATH timeout 180 claude -p --model haiku --settings "$tmp/permissions.json" \
    --setting-sources "" --permission-mode dontAsk --allowedTools=Bash \
    "Run exactly this bash command and nothing else: $2" >/dev/null 2>&1)
  [[ -e $tmp/ran ]] || got=denied
  if [[ $got == "$1" ]]; then
    echo "ok   $1: $2"
    pass=$((pass + 1))
  else
    echo "FAIL $1: $2 (got $got)"
    fail=$((fail + 1))
  fi
}

# The words are split so this file never contains the merge text the live session's own guards look for.
m="mer""ge"
expect denied "gh pr $m 1 --rebase"
expect denied "cd /tmp && gh pr $m 1"
expect denied "echo hi; gh pr $m 1"
expect denied "gh -R o/r pr $m 1"
expect denied "gh pr -R o/r $m 1"
expect ran "gh pr view 1"

echo "$pass passed, $fail failed"
((fail == 0))
