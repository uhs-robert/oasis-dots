#!/usr/bin/env bash
# Tests await.sh on logs in a scratch dir, and that check-in-background.sh leaves a call to it in the foreground.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
await=$here/../await.sh
hook=$here/../check-in-background.sh
pass=0 fail=0
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

# check <description> <condition...>
check() {
  local desc=$1
  shift
  if "$@"; then
    echo "ok   $desc"
    pass=$((pass + 1))
  else
    echo "FAIL $desc"
    fail=$((fail + 1))
  fi
}
exit_code_is() { [[ $code == "$1" ]]; }
output_has() { [[ $out == *"$1"* ]]; }
output_lacks() { [[ $out != *"$1"* ]]; }

seq 1 100 >"$scratch/pass.log"
sleep 0.05
echo 0 >"$scratch/pass.log.exit"
out=$("$await" "$scratch/pass.log" 5)
code=$?
check "finished pass exits 0" exit_code_is 0
check "finished pass prints the last log line" output_has 100
check "finished pass prints only the tail" output_lacks $'\n10\n'

seq 1 3 >"$scratch/fail.log"
sleep 0.05
echo 3 >"$scratch/fail.log.exit"
out=$("$await" "$scratch/fail.log" 5)
code=$?
check "finished fail passes the recorded code through" exit_code_is 3

printf 'step one\nstep two\n' >"$scratch/run.log"
start=$SECONDS
out=$("$await" "$scratch/run.log" 1)
code=$?
check "still running exits 75" exit_code_is 75
check "still running names the log's last line" output_has 'step two'
check "still running returns within the bound" test $((SECONDS - start)) -le 5

(sleep 1 && echo 0 >"$scratch/late.log.exit") &
echo late >"$scratch/late.log"
out=$("$await" "$scratch/late.log" 10)
code=$?
check "a run that finishes mid-wait is reported finished" exit_code_is 0

: >"$scratch/empty.log.exit"
out=$("$await" "$scratch/empty.log" 1 2>&1)
code=$?
check "an empty exit file (write in progress) is still running" exit_code_is 75

grep -qF "secs=\${2:-100}" "$await"
check "the default wait fits the default Bash timeout" test $? -eq 0

out=$("$await" "$scratch/absent.log" 1 2>&1)
code=$?
check "a missing log is still running (75), not an error" exit_code_is 75

out=$("$await" 2>&1)
code=$?
check "no argument is a usage error" test "$code" -ne 0

hook_out=$(jq -n --arg c ".claude/hooks/await.sh /tmp/x.log" '{tool_input: {command: $c}}' | "$hook")
check "the hook does not background await.sh" test -z "$hook_out"
hook_out=$(jq -n --arg c "lib/check.sh >/tmp/x.log 2>&1; echo \$? >/tmp/x.log.exit" '{tool_input: {command: $c}}' | "$hook")
check "the hook still backgrounds the log/exit form" test -n "$hook_out"

echo "$pass passed, $fail failed"
((fail == 0))
