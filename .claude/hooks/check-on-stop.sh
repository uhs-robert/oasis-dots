#!/usr/bin/env bash
# Stop: run `just check` when tracked files in the project checkout have uncommitted changes.
set -u
input=$(cat)
[[ $(jq -r '.stop_hook_active // false' <<<"$input") == true ]] && exit 0
dir=${CLAUDE_PROJECT_DIR:-$PWD}
[[ -n $(git -C "$dir" status --porcelain --untracked-files=no 2>/dev/null) ]] || exit 0

if out=$(cd "$dir" && timeout 180 just check 2>&1); then
  exit 0
fi
reason="'just check' failed in $dir with uncommitted changes to tracked files. Fix what it reports (or revert the change) before finishing. Last lines:
$(tail -n 20 <<<"$out")"
jq -n --arg r "$reason" '{decision: "block", reason: $r}'
