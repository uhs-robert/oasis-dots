#!/usr/bin/env bash
# Tests `hypr-act list` against a stub hyprctl and a fake runtime dir: the list is printed and the temp file removed;
# with no instance answering, or an eval that fails or writes nothing, stdout is empty, one line goes to stderr and the
# exit code is 3. The real Hyprland round trip is the shadow check in the PR.
set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
script=$here/../.local/bin/hypr-act
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

check() {
  if ! "$@"; then
    failures=$((failures + 1))
    echo "FAIL $*" >&2
  fi
}

mkdir -p "$work/bin"
# Behaviour is chosen per run by STUB_VERSION and STUB_EVAL: ok, fail or (eval only) empty.
cat >"$work/bin/hyprctl" <<'STUB'
#!/usr/bin/env bash
echo "$HYPRLAND_INSTANCE_SIGNATURE $*" >>"$STUB_LOG"
case $1 in
version) [[ ${STUB_VERSION:-ok} == ok ]] ;;
eval)
  [[ ${STUB_EVAL:-ok} != fail ]] || exit 1
  path=${2#*\[=====\[}
  path=${path%%\]=====\]*}
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
silent_failure() { [[ $status -eq 3 && ! -s $work/out && $(wc -l <"$work/err") -eq 1 ]]; }

mkdir -p "$work/run"
run list
check silent_failure

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

STUB_VERSION=fail run list
check silent_failure
STUB_EVAL=fail run list
check silent_failure
check no_stray_files
STUB_EVAL=empty run list
check silent_failure
check no_stray_files

# A dead newest instance falls back to the older one that answers.
cat >"$work/bin/hyprctl" <<'STUB'
#!/usr/bin/env bash
[[ $1 != version || $HYPRLAND_INSTANCE_SIGNATURE == old ]] || exit 1
[[ $1 != eval ]] || echo '{"version":1,"actions":[]}' >"$(sed -e 's/^[^[]*\[=====\[//' -e 's/\]=====\].*//' <<<"$2")"
STUB
run list
check test "$status" -eq 0

run bogus
check test "$status" -eq 2
run list extra
check test "$status" -eq 2

if [[ $failures -gt 0 ]]; then
  echo "$failures failed" >&2
  exit 1
fi
echo "hypr-act: all passed"
