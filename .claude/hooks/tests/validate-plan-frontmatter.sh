#!/usr/bin/env bash
# Feeds Write/Edit payloads to validate-plan-frontmatter.sh in a temp checkout: bad .plans front matter gets a steer, all else is silent.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
hook=$here/../validate-plan-frontmatter.sh
repo=$(cd "$here/../../.." && pwd)
pass=0 fail=0

root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
mkdir -p "$root/lib/check/steps" "$root/specs/schema" "$root/.plans/x" "$root/src"
cp "$repo/lib/check/steps/specs.py" "$root/lib/check/steps/"
cp "$repo/specs/schema/plan.yaml" "$root/specs/schema/"
good='---
kind: tracker
status: active
owner_session: none
updated: "2026-10-27"
specs: []
pr: none
---
# T
'
printf '%s' "$good" >"$root/.plans/x/good.md"
printf '%s' "$good" | sed 's/^pr: none$/pr: none\napproved: yes/' >"$root/.plans/x/bad.md"
printf '# no front matter\n' >"$root/.plans/x/none.md"
printf 'approved: yes\n' >"$root/.plans/x/bad.txt"
printf 'approved: yes\n' >"$root/src/foo.md"

# run <tool> <file> -> hook stdout; sets status
run() {
  out=$(jq -n --arg t "$1" --arg f "$2" '{tool_name: $t, tool_input: {file_path: $f}}' | "$hook")
  status=$?
}
ok() {
  echo "ok   $1"
  pass=$((pass + 1))
}
bad() {
  echo "FAIL $1"
  fail=$((fail + 1))
}

if command -v check-jsonschema >/dev/null; then
  for tool in Write Edit MultiEdit; do
    run "$tool" "$root/.plans/x/bad.md"
    ctx=$(jq -r '.hookSpecificOutput | select(.hookEventName == "PostToolUse") | .additionalContext' <<<"$out")
    if [[ $status == 0 && $ctx == *approved* && $ctx == *'just plan-new'* ]]; then ok "$tool bad key steers"; else bad "$tool bad key steers: $out"; fi
  done
  run Write "$root/.plans/x/none.md"
  if [[ $status == 0 && $out == *'no front matter'* ]]; then ok "no front matter steers"; else bad "no front matter steers: $out"; fi
  run Write "$root/.plans/x/good.md"
  if [[ $status == 0 && -z $out ]]; then ok "valid doc silent"; else bad "valid doc silent: $out"; fi
fi
run Write "$root/src/foo.md"
if [[ $status == 0 && -z $out ]]; then ok "non-plan path silent"; else bad "non-plan path silent: $out"; fi
run Write "$root/.plans/x/bad.txt"
if [[ $status == 0 && -z $out ]]; then ok "non-md silent"; else bad "non-md silent: $out"; fi
run Write "$root/.plans/x/missing.md"
if [[ $status == 0 && -z $out ]]; then ok "absent file silent"; else bad "absent file silent: $out"; fi
out=$(printf 'not json' | "$hook" 2>/dev/null)
if [[ $? == 0 && -z $out ]]; then ok "bad input exits 0"; else bad "bad input exits 0"; fi

echo "$pass passed, $fail failed"
((fail == 0))
