#!/usr/bin/env bash
# Feeds commands to guard-wait-loops.sh: a wait loop on a literal pgrep -f pattern is denied, safe forms pass.
set -uo pipefail
hook=$(cd "$(dirname "$0")" && pwd)/../guard-wait-loops.sh
pass=0 fail=0

# expect <allow|deny> <command>
expect() {
  local out got=allow
  out=$(jq -n --arg c "$2" '{tool_input: {command: $c}}' | "$hook" | jq -r '.hookSpecificOutput.permissionDecision // empty')
  [[ $out == deny ]] && got=deny
  if [[ $got == "$1" ]]; then
    echo "ok   $1: $2"
    pass=$((pass + 1))
  else
    echo "FAIL $1: $2 (got $got)"
    fail=$((fail + 1))
  fi
}

# The loops that ran for hours.
expect deny 'until ! pgrep -f "test/key/run.mjs" >/dev/null; do sleep 5; done'
expect deny 'while pgrep -f "test/key/run.mjs" >/dev/null; do sleep 5; done'
expect deny 'until grep -q "=== p98" /tmp/log && ! pgrep -f "key/run.mjs" >/dev/null; do sleep 5; done'
expect deny 'until ! pgrep -f "KEY_TEST_ORDER=reverse just key-test > /tmp/r1" >/dev/null; do :; done 2>/dev/null & sleep 0; echo skip'

# Other spellings of the same loop.
expect deny 'while pgrep --full lit; do sleep 1; done'
expect deny 'while pgrep -af lit; do sleep 1; done'
# shellcheck disable=SC2016 # the command text is data, not expanded here
expect deny 'while [ -n "$(pgrep -f lit)" ]; do sleep 1; done'
expect deny $'until ! pgrep -f lit\ndo\n\tsleep 1\ndone'
expect deny 'echo start; while pgrep -f lit; do sleep 1; done'
expect deny 'timeout 1s true; while pgrep -f lit; do sleep 1; done'
expect deny 'timeout 1s true && until ! pgrep -f "a/b" ; do sleep 1; done'
expect deny 'timeout 1s true;while pgrep -f lit; do sleep 1; done'
# shellcheck disable=SC2016
expect deny 'while pgrep -u "$USER" -f lit; do sleep 1; done'
expect deny $'cat <<<hi\nwhile pgrep -f lit; do sleep 1; done'
expect deny '(timeout 1s true); { while pgrep -f lit; do sleep 1; done; }'
expect deny 'while pgrep -f one && pgrep -f "t[w]o"; do sleep 1; done'

# Safe forms.
expect allow 'pgrep -f lit'
# shellcheck disable=SC2016
expect allow '[ -z "$(pgrep -f lit)" ] && echo gone'
expect allow "pgrep -f '[p]attern'"
expect allow "while pgrep -f '[k]ey/run.mjs'; do sleep 1; done"
# shellcheck disable=SC2016
expect allow 'while pgrep -f "$pat"; do sleep 1; done'
expect allow 'timeout 600 bash -c "until ! pgrep -f lit; do sleep 1; done"'
expect allow 'timeout 600 bash -c "while pgrep -f lit; do sleep 1; done"'
expect allow 'while pgrep lit; do sleep 1; done'
# shellcheck disable=SC2016
expect allow 'while kill -0 $pid; do sleep 1; done'
expect allow 'until [ -f /tmp/done ]; do sleep 1; done'
# shellcheck disable=SC2016
expect allow 'tail --pid=$pid -f /dev/null'
expect allow 'pgrep -f lit; while true; do sleep 1; break; done'
# shellcheck disable=SC2016
expect allow 'for p in $(pgrep -f lit); do echo $p; done'
# Quoted text that only mentions a loop is not a loop.
expect allow 'git commit -m "fix: while pgrep -f x; do sleep 1; done"'
expect allow 'echo "while pgrep -f x; do sleep 1; done" > f'
expect allow "gh pr create --body 'until ! pgrep -f x; do :; done'"
expect allow $'cat <<EOF\nwhile pgrep -f lit; do sleep 1; done\nEOF'

echo "$pass passed, $fail failed"
((fail == 0))
