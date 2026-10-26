#!/usr/bin/env bash
# Tests `hypr-act list` and `hypr-act <id> [args]` against a stub hyprctl and a fake runtime dir: the list is printed
# and the temp file removed; with no instance answering, or an eval that fails or writes nothing, stdout is empty, one
# line goes to stderr and the exit code is 3 or 4. A run evals real Lua: the stub executes the chunk against a fake
# lib.act that records the id and words it receives, so quoting is proven end to end. The real Hyprland round trip
# (including that `hyprctl eval` exits non-zero on a Lua error) is the shadow check in the PR.
set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
script=$here/../.local/bin/hypr-act
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

# Run from the temp dir: a stub or script that writes to a path built from an argument lands here, never in the repo.
cd "$work" || exit 1

check() {
  if ! "$@"; then
    failures=$((failures + 1))
    echo "FAIL $*" >&2
  fi
}

mkdir -p "$work/bin"
# Behaviour is chosen per run by STUB_VERSION and STUB_EVAL: ok, fail, empty, hang (outlasts the timeout) or late
# (answers ok at once and writes its file a second later, after hypr-act has given up).
cat >"$work/bin/hyprctl" <<'STUB'
#!/usr/bin/env bash
echo "$HYPRLAND_INSTANCE_SIGNATURE $*" >>"$STUB_LOG"
case $1 in
version) [[ ${STUB_VERSION:-ok} == ok ]] ;;
eval)
  [[ ${STUB_EVAL:-ok} != fail ]] || exit 1
  if [[ $2 == *run_cli* ]]; then
    [[ ${STUB_EVAL:-ok} != hang ]] || exec sleep 5
    # Like hyprctl eval: a Lua error prints its message and exits non-zero.
    lua -e 'package.preload["lib.act"] = function()
      return { run_cli = function(id, words)
        if id == "boom.now" then error("action failed: boom", 0) end
        local file = assert(io.open(os.getenv("STUB_ARGS"), "wb"))
        file:write(id, "\0", table.concat(words, "\0"), #words > 0 and "\0" or "")
        file:close()
      end }
    end' -e "$2" || exit 1
    echo ok
    exit 0
  fi
  path=${2#*\[=====\[}
  path=${path%%\]=====\]*}
  [[ ${STUB_EVAL:-ok} != hang ]] || exec sleep 5
  if [[ ${STUB_EVAL:-ok} == late ]]; then
    (
      sleep 1
      echo '{"version":1,"actions":[]}' >"$path"
    ) &
    echo ok
    exit 0
  fi
  [[ ${STUB_EVAL:-ok} == empty ]] || echo '{"version":1,"actions":[]}' >"$path"
  echo ok
  ;;
esac
STUB
chmod +x "$work/bin/hyprctl"

run() {
  : >"$work/log"
  XDG_RUNTIME_DIR=$work/run PATH=$work/bin:$PATH STUB_LOG=$work/log "$script" "$@" >"$work/out" 2>"$work/err"
  status=$?
}
no_stray_files() { [[ -z $(find "$work/run" -maxdepth 1 -name 'hypr-act.*') ]]; }
silent_failure() { [[ $status -eq ${1:-3} && ! -s $work/out && $(wc -l <"$work/err") -eq 1 ]]; }

mkdir -p "$work/run"
run list
check silent_failure 3

# The newest answering instance gets the eval.
for instance in old new; do
  mkdir -p "$work/run/hypr/$instance"
  : >"$work/run/hypr/$instance/.socket.sock"
  touch -d "$([[ $instance == old ]] && echo '2 minutes ago' || echo '1 minute ago')" "$work/run/hypr/$instance/.socket.sock"
done
run list
check test "$status" -eq 0
check test "$(cat "$work/out")" = '{"version":1,"actions":[]}'
check grep -q '^new eval ' "$work/log"
check no_stray_files

# No instance answering is "not running" (3); every failure past that point is "running but unreadable" (4).
STUB_VERSION=fail run list
check silent_failure 3
check grep -q 'not running' "$work/err"
STUB_EVAL=fail run list
check silent_failure 4
check grep -q 'is running' "$work/err"
check no_stray_files
STUB_EVAL=empty run list
check silent_failure 4
check no_stray_files
HYPR_ACT_TIMEOUT=1 STUB_EVAL=hang run list
check silent_failure 4
check grep -q 'is running' "$work/err"
check no_stray_files

# An eval that writes after hypr-act gave up leaves nothing behind: its directory is already gone.
STUB_EVAL=late run list
check silent_failure 4
sleep 1.5
check no_stray_files

# Running an action: the id and every word reach Act.run_cli verbatim, whatever they hold.
if command -v lua >/dev/null; then
  run_args() {
    export STUB_ARGS=$work/args
    rm -f "$STUB_ARGS"
    run "$@"
  }
  args_are() { # the id and words the fake run_cli saw, each NUL-terminated
    printf '%s\0' "$@" | cmp -s - "$STUB_ARGS"
  }
  run_args picker.clipboard
  check test "$status" -eq 0
  check test ! -s "$work/out"
  check test ! -s "$work/err"
  check args_are picker.clipboard
  check grep -q '^new eval ' "$work/log"

  # shellcheck disable=SC2016  # the literal $(...) must reach the stub unexpanded
  hostile_words=(
    'a]]b' ']=]' ']=====]' 'x==y]======]z' "it's" 'say "hi"' 'two words' $'new\nline' $'\nlead' $'trail\n' '$(touch x)' "\\" '-x' ''
  )
  run_args zoom.set "${hostile_words[@]}"
  check test "$status" -eq 0
  check args_are zoom.set "${hostile_words[@]}"

  # An id is quoted like a word.
  run_args 'a]]b'
  check args_are 'a]]b'

  # A Lua error exits 5 with hyprctl's message on stderr and nothing on stdout.
  run_args boom.now
  check test "$status" -eq 5
  check test ! -s "$work/out"
  check grep -q 'action failed: boom' "$work/err"

  # No instance answering is 3 for a run too.
  STUB_VERSION=fail run_args picker.clipboard
  check test "$status" -eq 3
  check grep -q 'not running' "$work/err"

  # A run past the timeout and a failing hyprctl are failed actions.
  HYPR_ACT_TIMEOUT=1 STUB_EVAL=hang run_args picker.clipboard
  check test "$status" -eq 5
  check grep -q 'did not finish' "$work/err"
  STUB_EVAL=fail run_args picker.clipboard
  check test "$status" -eq 5
fi

# A dead newest instance falls back to the older one that answers.
cat >"$work/bin/hyprctl" <<'STUB'
#!/usr/bin/env bash
[[ $1 != version || $HYPRLAND_INSTANCE_SIGNATURE == old ]] || exit 1
[[ $1 != eval || $2 != *write_list* ]] || echo '{"version":1,"actions":[]}' >"$(sed -e 's/^[^[]*\[=====\[//' -e 's/\]=====\].*//' <<<"$2")"
STUB
run list
check test "$status" -eq 0

run list extra
check test "$status" -eq 2

# An empty id and anything that looks like a flag are usage errors, and nothing reaches hyprctl.
for bad in '' --help -h --foo; do
  run "$bad"
  check test "$status" -eq 2
  check test ! -s "$work/log"
done
run
check test "$status" -eq 2

# No stray file in the repo: a stub that wrote to a path built from an argument would leave an untracked one.
if git -C "$here" rev-parse --git-dir >/dev/null 2>&1; then
  check test -z "$(git -C "$here" ls-files --others --exclude-standard -- ..)"
fi

if [[ $failures -gt 0 ]]; then
  echo "$failures failed" >&2
  exit 1
fi
echo "hypr-act: all passed"
