#!/usr/bin/env bash
# Feeds commands to check-in-background.sh: a command that runs the check starts in the background, one that only
# mentions it does not.
set -uo pipefail
hook=$(cd "$(dirname "$0")" && pwd)/../check-in-background.sh
pass=0 fail=0

# expect <bg|fg> <command>
expect() {
  local out got=fg
  out=$(jq -n --arg c "$2" '{tool_input: {command: $c}}' | "$hook" | jq -r '.hookSpecificOutput.updatedInput.run_in_background // empty')
  [[ $out == true ]] && got='bg'
  if [[ $got == "$1" ]]; then
    echo "ok   $1: ${2//$'\n'/\\n}"
    pass=$((pass + 1))
  else
    echo "FAIL $1: ${2//$'\n'/\\n} (got $got)"
    fail=$((fail + 1))
  fi
}

expect bg 'just check'
expect bg 'lib/check.sh'
expect bg 'cd x && just check'
expect bg 'FOO=1 timeout 5 lib/check.sh'

# A command on a later line or after a CRLF is a command start.
expect bg $'echo hi\njust check'
expect bg $'echo hi\nlib/check.sh --fast'
expect bg $'echo hi\r\njust check'
expect bg $'if true; then\n  just check\nfi'

# Paths that are only arguments, and a stray "n" before the command name, are not command starts.
expect fg 'echo n just check'
expect fg $'echo hi\rjust check'
expect fg 'git diff lib/check.sh'
expect fg 'shellcheck lib/check.sh'
expect fg $'echo hi\ngit diff lib/check.sh'
expect fg 'just check --plan'

echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
