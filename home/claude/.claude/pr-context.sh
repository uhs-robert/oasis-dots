#!/usr/bin/env bash
# Background refresher: resolve the current branch to a PR or issue label, cached for the statusline.
repo_root=$1
branch=$2
cache=$3

label=""
if command -v gh >/dev/null 2>&1; then
  label=$(cd "$repo_root" && timeout 15 gh pr view --json number,title \
    --jq '"PR " + (.number|tostring) + " " + .title' 2>/dev/null)
fi

if [ -z "$label" ]; then
  num=$(printf '%s' "$branch" | grep -oE '(^|[^0-9])([0-9]{1,6})([^0-9]|$)' | grep -oE '[0-9]{1,6}' | head -1)
  if [ -n "$num" ] && command -v gh >/dev/null 2>&1; then
    label=$(cd "$repo_root" && timeout 15 gh issue view "$num" --json number,title \
      --jq '"Issue " + (.number|tostring) + " " + .title' 2>/dev/null)
  fi
fi

printf '%s' "$(printf '%s' "$label" | tr -d '\000-\037' | head -c 60)" > "$cache.tmp" 2>/dev/null
mv -f "$cache.tmp" "$cache" 2>/dev/null
