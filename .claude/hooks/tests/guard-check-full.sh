#!/usr/bin/env bash
# Feeds Bash commands to guard-check-full.sh against a throwaway repo with and without a recorded pass.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
hook=$here/../guard-check-full.sh
repo_lib=$here/../../../lib
pass=0 fail=0
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
g() { git -C "$repo" -c user.name=t -c user.email=t@t "$@"; }

repo=$root/repo
git init -q --bare -b main "$root/origin.git"
git clone -q "$root/origin.git" "$repo" 2>/dev/null
mkdir -p "$repo/lib/check"
cp "$repo_lib/check/passed.sh" "$repo_lib/check/passed.py" "$repo/lib/check/"
g add -A
g commit -qm base
g push -q origin main 2>/dev/null
g switch -q -c topic
echo change >"$repo/file"
g add -A
g commit -qm change
base=$(g rev-parse origin/main)
log=$root/reasons.log
export CHECK_FULL_REASONS_LOG=$log

# run <command>: the hook's raw output
run() { jq -n --arg c "$1" --arg d "$repo" '{tool_input: {command: $c}, cwd: $d}' | "$hook"; }
# expect <allow|deny> <description> <command>
expect() {
  local out decision
  out=$(run "$3")
  decision=$(jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"${out:-{\}}")
  if [[ $decision == "$1" ]]; then
    echo "ok   $1: $2"
    pass=$((pass + 1))
  else
    echo "FAIL $1: $2 (got $decision)"
    fail=$((fail + 1))
  fi
}
check() {
  if eval "$2"; then
    echo "ok   $1"
    pass=$((pass + 1))
  else
    echo "FAIL $1"
    fail=$((fail + 1))
  fi
}

expect allow "no pass recorded" "CHECK_FULL=1 lib/check.sh --changed $base"
(cd "$repo" && lib/check/passed.sh record-changed "$base")
expect allow "no CHECK_FULL" "lib/check.sh --changed $base"
expect allow "CHECK_FULL for another command" "CHECK_FULL=1 echo hi"
expect deny "env prefix" "CHECK_FULL=1 lib/check.sh --changed $base"
expect deny "export" "export CHECK_FULL=1; lib/check.sh"
expect deny "env command" "env CHECK_FULL=1 lib/check.sh --changed $base"
expect deny "just check" "CHECK_FULL=1 just check"
expect allow "CHECK_FULL=0" "CHECK_FULL=0 lib/check.sh"
check "nothing logged yet" "[[ ! -e $log ]]"
expect allow "reason set" "CHECK_FULL_REASON=\"shader cache is stale\" CHECK_FULL=1 lib/check.sh"
check "log line has timestamp, worktree, branch, head and reason" \
  "grep -qP '^\d{4}-.*\t$repo\ttopic\t$(g rev-parse --short HEAD)\tshader cache is stale\$' $log"
check "reason is echoed into the transcript" "run 'CHECK_FULL=1 CHECK_FULL_REASON=bare lib/check.sh' | jq -e '.hookSpecificOutput.additionalContext | contains(\"bare\")' >/dev/null"
check "two reasons, two lines" "[[ \$(wc -l <$log) -eq 2 ]]"
expect deny "an empty reason does not count" "CHECK_FULL_REASON= CHECK_FULL=1 lib/check.sh"
echo new >"$repo/untracked"
expect allow "a new untracked file: the runner reads it too" "CHECK_FULL=1 lib/check.sh"
rm "$repo/untracked"
expect deny "clean again" "CHECK_FULL=1 lib/check.sh"
echo dirty >>"$repo/file"
expect allow "uncommitted edits: the inputs differ from the record" "CHECK_FULL=1 lib/check.sh"

echo "$pass passed, $fail failed"
((fail == 0))
