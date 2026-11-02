#!/usr/bin/env bash
# Tests bin/hypr-live against a stub hyprctl and fake runtime dirs: the newest answering instance wins, an instance whose
# lock PID is gone is skipped without a probe, a hung one falls through to the next, none answering exits 1, and a valid
# signature in the environment is kept. --owner maps a shadow runtime dir to the owner's and never returns the nested
# instance; --env prints the pair a caller exports.
set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
script=$here/../.local/bin/hypr-live
work=$(mktemp -d)
# The shadow runtime dir must match /tmp/shadow-*, so it cannot sit under $work.
shadow_run=$(mktemp -d /tmp/shadow-hypr-live-test.XXXXXX)
trap 'rm -rf "$work" "$shadow_run"' EXIT
failures=0
cd "$work" || exit 1

check() {
  if ! "$@"; then
    failures=$((failures + 1))
    echo "FAIL $*" >&2
  fi
}
# shellcheck disable=SC2329 # called through check
not() { ! "$@"; }

mkdir bin
# Answers only for signatures listed in $STUB_LIVE (one per line), under the runtime dir it was given; hangs for those in
# $STUB_HANG. Logs each call as "<runtime> <signature> <args>".
cat >bin/hyprctl <<'STUB'
#!/usr/bin/env bash
echo "$XDG_RUNTIME_DIR $HYPRLAND_INSTANCE_SIGNATURE $*" >>"$STUB_LOG"
[[ -e $XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket.sock ]] || exit 1
if grep -qx "$HYPRLAND_INSTANCE_SIGNATURE" "$STUB_HANG" 2>/dev/null; then exec sleep 10; fi
grep -qx "$HYPRLAND_INSTANCE_SIGNATURE" "$STUB_LIVE"
STUB
chmod +x bin/hyprctl
export PATH=$work/bin:$PATH STUB_LOG=$work/log STUB_LIVE=$work/live STUB_HANG=$work/hang

# instance <runtime> <name> <age> [lock pid]: a socket of the given age, and a lock when a pid is given.
instance() {
  mkdir -p "$1/hypr/$2"
  : >"$1/hypr/$2/.socket.sock"
  touch -d "$3" "$1/hypr/$2/.socket.sock"
  [[ -z ${4:-} ]] || printf '%s\nwayland-1\n' "$4" >"$1/hypr/$2/hyprland.lock"
}
dead_pid() {
  local pid
  sleep 0 &
  pid=$!
  wait "$pid"
  echo "$pid"
}
# run <runtime> [env assignments] -- [args]: output in out, errors in err, exit code in status.
run() {
  local runtime=$1
  shift
  local assigns=()
  while (($#)) && [[ $1 != -- ]]; do
    assigns+=("$1")
    shift
  done
  shift
  : >"$work/log"
  env -u HYPRLAND_INSTANCE_SIGNATURE -u OWNER_RUNTIME_DIR XDG_RUNTIME_DIR="$runtime" "${assigns[@]}" "$script" "$@" >"$work/out" 2>"$work/err"
  status=$?
}
# shellcheck disable=SC2329 # called through check
probed() { grep -q " $1 " "$work/log"; }
# shellcheck disable=SC2329 # called through check
said() { [[ $(cat "$work/out") == "$1" ]]; }

run_dir=$work/run
alive=$$
gone=$(dead_pid)
instance "$run_dir" old '3 minutes ago' $alive
instance "$run_dir" new '1 minute ago' $alive
printf 'old\nnew\n' >live

run "$run_dir" --
check test "$status" -eq 0
check said new
check test ! -s err

# A dead newest instance (lock PID gone) is skipped without a probe.
instance "$run_dir" newest 'now' "$gone"
printf 'old\nnew\nnewest\n' >live
run "$run_dir" --
check said new
check not probed newest

# A lock that is missing counts as live, so the probe decides.
rm "$run_dir/hypr/newest/hyprland.lock"
run "$run_dir" --
check said newest
check probed newest

# A reused PID (the lock names a live process that is not Hyprland) is not trusted: the probe still decides.
printf '%s\nwayland-1\n' $alive >"$run_dir/hypr/newest/hyprland.lock"
printf 'old\nnew\n' >live
run "$run_dir" --
check said new
check probed newest

# A hung newest instance falls through to the older one after the timeout.
echo newest >hang
printf 'old\nnew\nnewest\n' >live
SECONDS=0
run "$run_dir" --
check said new
check test "$SECONDS" -ge 3
: >hang

# Each lookup is fresh: once the instance that answered is gone, the next call finds the one behind it.
printf 'new\n' >live
run "$run_dir" --
check said new
printf 'old\n' >live
run "$run_dir" --
check said old

# None answering exits 1 with one line on stderr and an empty stdout.
: >live
run "$run_dir" --
check test "$status" -eq 1
check test ! -s out
check test "$(wc -l <err)" -eq 1
check grep -q 'no Hyprland instance answered' err
run "$work/empty" --
check test "$status" -eq 1

# The probe is a parameter.
printf 'old\n' >live
run "$run_dir" -- --probe monitors
check said old
check grep -q ' old monitors' log

# --env prints the pair to export.
run "$run_dir" -- --env
check test "$(cat out)" = "$(printf 'HYPRLAND_INSTANCE_SIGNATURE=old\nXDG_RUNTIME_DIR=%s' "$run_dir")"

# A stale signature in the environment gives way to the instance that answers.
printf 'old\nnew\n' >live
run "$run_dir" HYPRLAND_INSTANCE_SIGNATURE=gone --
check said new
check test ! -s err
# A valid one is kept, even when a newer instance exists.
run "$run_dir" HYPRLAND_INSTANCE_SIGNATURE=old --
check said old
# A stale one whose lock PID is gone is not probed.
instance "$run_dir" stale '2 days ago' "$gone"
run "$run_dir" HYPRLAND_INSTANCE_SIGNATURE=stale --
check said new
check not probed stale
# A signature that is a path is ignored.
run "$run_dir" HYPRLAND_INSTANCE_SIGNATURE=../x --
check said new

# Bad usage.
run "$run_dir" -- --bogus
check test "$status" -eq 2
run "$run_dir" -- --probe
check test "$status" -eq 2

# Inside a shadow, --owner looks in the owner's runtime dir and refuses the nested instance, with or without its signature.
owner_run=$work/owner
instance "$owner_run" live '1 hour ago' $alive
instance "$shadow_run" nested 'now' $alive
printf 'live\nnested\n' >live
run "$shadow_run" OWNER_RUNTIME_DIR="$owner_run" -- --owner
check said live
check not grep -q nested log
run "$shadow_run" OWNER_RUNTIME_DIR="$owner_run" HYPRLAND_INSTANCE_SIGNATURE=nested -- --owner --env
check test "$(cat out)" = "$(printf 'HYPRLAND_INSTANCE_SIGNATURE=live\nXDG_RUNTIME_DIR=%s' "$owner_run")"
check not grep -q nested log
printf 'nested\n' >live
run "$shadow_run" OWNER_RUNTIME_DIR="$owner_run" -- --owner
check test "$status" -eq 1
check not grep -q nested log
# Without --owner the shadow's own instance is what answers, so the shadow bar keeps its own Hyprland.
run "$shadow_run" --
check said nested

# The wallpaper script's lookup shells out to hypr-live; a stub on PATH stands in for it. Its answer says whether the
# environment signature reached it, which skip_env must prevent.
if command -v lua >/dev/null; then
  ext=$here/../.config/hypr
  apply=$ext/extensions/wallpaper/lib/apply.lua
  mkdir stub_live
  cat >stub_live/hypr-live <<'STUB'
#!/usr/bin/env bash
[[ -e $STUB_NONE ]] && exit 1
echo "found-${HYPRLAND_INSTANCE_SIGNATURE:-unset}"
STUB
  chmod +x stub_live/hypr-live
  detect() {
    PATH=$work/stub_live:$PATH STUB_NONE=$work/none HYPRLAND_INSTANCE_SIGNATURE=env lua -e "
      package.path = '$ext/?.lua;$ext/?/init.lua;' .. package.path
      local apply = dofile('$apply')
      print(apply.detect_signature($1) or 'nil')"
  }
  check test "$(detect '')" = found-env
  check test "$(detect true)" = found-unset
  : >none
  check test "$(detect '')" = nil
  rm none
fi

exit $((failures > 0))
