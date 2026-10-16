#!/bin/bash
# Tests the heavy-step slots of lib/check/lock.sh in a runtime dir of its own, so the machine's real slots are untouched.
set -u
unset CHECK_LOCK_HELD CHECK_NO_LOCK CHECK_HEAVY_SLOTS CHECK_LOCK_WAIT_SECS SANDBOX_REAL_XDG_RUNTIME_DIR
lock_lib=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)/lock.sh
scratch=$(mktemp -d) || exit 1
holders=''
trap 'kill $holders 2>/dev/null; rm -rf "$scratch"' EXIT
export XDG_RUNTIME_DIR=$scratch

failures=0
expect() {
  if eval "$2"; then printf 'ok   %s\n' "$1"; else
    printf 'FAIL %s\n' "$1" >&2
    failures=$((failures + 1))
  fi
}
command -v flock >/dev/null || {
  echo 'skip: the slot tests need flock'
  exit 0
}

# Starts a holder that keeps its slot until its marker file is removed; prints its pid once it holds the slot.
hold_slot() {
  marker=$scratch/hold.$1
  : >"$marker"
  sh -c '. "$1"; check_lock_take "holder $2" || exit 1; : >"$3.held"; while [ -e "$3" ]; do sleep 0.1; done' _ "$lock_lib" "$1" "$marker" &
  holders="$holders $!"
  for _ in $(seq 50); do
    [ -e "$marker.held" ] && return 0
    sleep 0.1
  done
  return 1
}
try_take() { CHECK_LOCK_WAIT_SECS=${1:-0} sh -c '. "$1"; check_lock_take tester' _ "$lock_lib" 2>"$scratch/err"; }

# One slot by default: the click suite alone keeps the machine busy, and two at once make its timing flaky.
expect "a first holder takes the one default slot" "hold_slot only"
expect "a second waits for it, then gives up" "! try_take 1"
rm "$scratch/hold.only"
expect "and gets it once it frees" "try_take 5"

export CHECK_HEAVY_SLOTS=2
expect "a first holder takes a slot" "hold_slot one"
expect "a second holder takes the other slot" "hold_slot two"
expect "a third waits, then gives up" "! try_take 1"
expect "naming the holders" "grep -q 'holder one' '$scratch/err' && grep -q 'holder two' '$scratch/err'"
expect "CHECK_NO_LOCK runs without a slot" "CHECK_NO_LOCK=1 try_take"
expect "a run under a slot holder takes none" "CHECK_LOCK_HELD=1 try_take"
expect "CHECK_HEAVY_SLOTS=3 opens a third slot" "CHECK_HEAVY_SLOTS=3 try_take"
rm "$scratch/hold.one"
expect "a waiting run gets a slot once one frees" "try_take 5"

expect "a holder retakes the free slot" "hold_slot three"
kill -9 "${holders##* }"
wait "${holders##* }" 2>/dev/null
expect "a holder killed outright frees its slot" "try_take 2"

# A suite gated by check_lock_gate runs its body without fd 7, so nothing it leaves running can keep the slot.
cat >"$scratch/suite.sh" <<EOF
#!/bin/sh
. "$lock_lib"
check_lock_gate suite "\$0" "\$@"
ls -l /proc/\$\$/fd/7 >/dev/null 2>&1 && echo has-fd7 || echo no-fd7
echo "held=\$CHECK_LOCK_HELD nice=\$(ps -o ni= -p \$\$ | tr -d ' ')"
EOF
chmod +x "$scratch/suite.sh"
rm "$scratch/hold.two"
sleep 0.3
out=$("$scratch/suite.sh")
expect "a gated suite runs its body under a slot, without the slot's fd" "[ '$(printf '%s' "$out" | head -n 1)' = no-fd7 ] && printf '%s' '$out' | grep -q 'held=1'"
expect "at nice 19" "printf '%s' '$out' | grep -q 'nice=19'"

[ "$failures" = 0 ] || {
  printf '%s failed\n' "$failures" >&2
  exit 1
}
echo 'all slot cases passed'
