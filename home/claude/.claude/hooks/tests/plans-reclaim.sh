#!/usr/bin/env bash
# Tests for plans-reclaim.sh: the hook passes its input to `plans reclaim`, prints nothing and exits 0 whatever
# `plans` does, including when it is missing. HOME is a temp dir, so no test reaches real plan docs.
set -u
# The real path, because ~/.claude links here and the plans entry is found relative to the repo.
here=$(dirname "$(realpath "$0")")
hook="$here/../plans-reclaim.sh"
entry="$here/../../../../plans/.local/bin/plans"
[[ -x $entry ]] || entry=$(command -v plans || true)
failures=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
unset CLAUDE_PID GITHUB_DIR PLANS_SESSION

check() {
  local name=$1
  shift
  if "$@"; then echo "ok   $name"; else
    echo "FAIL $name"
    failures=$((failures + 1))
  fi
}

run_hook() { # $1 hook input; sets out and code
  out=$(printf '%s' "$1" | HOME="$tmp/home" bash "$hook" 2>&1)
  code=$?
}

silent_ok() { [[ $code -eq 0 && -z $out ]]; }

mkdir -p "$tmp/home"
run_hook '{"session_id":"s1"}'
check "no plans command is silent and ok" silent_ok

mkdir -p "$tmp/home/.local/bin"
cat >"$tmp/home/.local/bin/plans" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >"$tmp/args"
cat >"$tmp/stdin"
echo "noise on stdout"
echo "noise on stderr" >&2
exit 3
STUB
chmod +x "$tmp/home/.local/bin/plans"
run_hook '{"session_id":"s1","source":"resume"}'
check "a failing plans is silent and ok" silent_ok
check "plans gets the reclaim command" test "$(cat "$tmp/args")" = reclaim
check "plans gets the hook input" test "$(cat "$tmp/stdin")" = '{"session_id":"s1","source":"resume"}'

if [[ -z $entry ]]; then
  echo "skip the real plans checks: no plans entry found"
else
  ln -sf "$entry" "$tmp/home/.local/bin/plans"
  for input in 'not json' '[1]' '{}' '{"session_id":5}' ''; do
    run_hook "$input"
    check "the real plans is silent and ok on input '$input'" silent_ok
  done
fi

((failures == 0)) || exit 1
